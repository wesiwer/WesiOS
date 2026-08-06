import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:local_notifier/local_notifier.dart';

/// О чём уведомление. От вида зависит и то, можно ли его выключить
/// отдельно, и то, насколько настойчиво оно выглядит.
enum NotifyKind {
  /// Просрочка, срок, списание, минус на счету — всё, что считает
  /// колокольчик на главной.
  alert,

  /// Пришло сообщение.
  message,

  /// Обмен с сервером сорвался.
  sync,

  /// Вышла новая версия.
  update,
}

/// Одно уведомление.
class WesiNotification {
  const WesiNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.route,
  });

  /// Отпечаток события, а не порядковый номер.
  ///
  /// По нему решается, показывали это уже или нет. Счётчик здесь не
  /// годится: события не хранятся, а вычисляются заново при каждом
  /// изменении данных, и «уведомление №7» после перезапуска — уже другое
  /// событие.
  final String id;

  final String title;
  final String body;
  final NotifyKind kind;

  /// Куда вести по нажатию.
  final String? route;
}

/// Куда уходит уведомление. Разделено интерфейсом, потому что платформ
/// две с половиной, а проверять надо решение «показывать или молчать».
abstract class NotificationBackend {
  Future<void> init();

  Future<void> show(WesiNotification notification);
}

/// Системные уведомления: телефон и компьютер.
///
/// **Почему две библиотеки.** `flutter_local_notifications` не умеет
/// Windows — ни в одной версии, совместимой с этим проектом. `local_notifier`
/// не умеет Android. Каждая из них покрывает то, что покрывает, и выбор
/// между ними — не архитектура, а факт.
///
/// **Почему первый запуск молчит.** На старте состояние уже накоплено:
/// три просроченные задачи, минус на счету, вышедшее обновление. Показать
/// это всё пачкой при первом же открытии — верный способ, чтобы человек
/// выключил уведомления и никогда не включил обратно. Поэтому существующее
/// на момент запуска запоминается как «уже видел» и молча, а уведомления
/// приходят только на то, что появилось после.
class WesiNotifications {
  const WesiNotifications._();

  static const String _box = 'wesios_settings';
  static const String _enabledKey = 'notify_enabled';
  static const String _kindKeyPrefix = 'notify_kind_';
  static const String _seenKey = 'notify_seen';

  /// Меняется при переключении — экран настроек перечитывает.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Что показалось последним. Нужно экранам и тестам.
  static final ValueNotifier<WesiNotification?> last =
      ValueNotifier<WesiNotification?>(null);

  static NotificationBackend? _backend;
  static bool _ready = false;

  /// Подменяется в тестах: настоящие уведомления там показать негде, а
  /// проверять надо, что решение принято верно.
  @visibleForTesting
  static set backend(NotificationBackend? value) {
    _backend = value;
    _ready = value != null;
  }

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────── настройки

  /// Умеет ли эта платформа показывать системные уведомления.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  static bool get enabled =>
      isSupported && _open()?.get(_enabledKey) != false;

  static Future<void> setEnabled(bool on) async {
    await _open()?.put(_enabledKey, on);
    revision.value++;
  }

  static bool kindEnabled(NotifyKind kind) =>
      _open()?.get('$_kindKeyPrefix${kind.name}') != false;

  static Future<void> setKindEnabled(NotifyKind kind, bool on) async {
    await _open()?.put('$_kindKeyPrefix${kind.name}', on);
    revision.value++;
  }

  // ─────────────────────────────────────────────────── уже показанное

  static Set<String>? _seenCache;

  static Set<String> get _seen {
    final cached = _seenCache;
    if (cached != null) return cached;
    final raw = _open()?.get(_seenKey);
    return _seenCache =
        raw is List ? raw.map((e) => '$e').toSet() : <String>{};
  }

  static void _persistSeen() {
    // Держим последнюю тысячу: список отпечатков не должен расти вечно, а
    // тысяча событий — это заведомо больше, чем успеет случиться между
    // запусками.
    final ids = _seen.toList();
    final kept = ids.length <= 1000 ? ids : ids.sublist(ids.length - 1000);
    _seenCache = kept.toSet();
    _open()?.put(_seenKey, kept);
  }

  /// Запомнить событие как показанное, ничего не показывая.
  ///
  /// Первый запуск после установки и каждый запуск программы: то, что уже
  /// накопилось, человек и так увидит на главной, а десять уведомлений
  /// подряд он увидит один раз — перед тем как всё выключить.
  static void markSeen(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (_seen.add(id)) changed = true;
    }
    if (changed) _persistSeen();
  }

  static bool wasSeen(String id) => _seen.contains(id);

  // ─────────────────────────────────────────────────────────── показ

  static Future<void> init() async {
    if (_ready) return;
    _backend ??= _pickBackend();
    try {
      await _backend?.init();
      _ready = true;
    } catch (_) {
      // Не выдали разрешение, нет службы уведомлений, экзотическая сборка
      // Linux без демона — приложение обязано работать дальше.
      _ready = false;
    }
  }

  static NotificationBackend? _pickBackend() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return _MobileBackend();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return _DesktopBackend();
    }
    return null;
  }

  /// Показать, если это ещё не показывали и вид не выключен.
  ///
  /// Возвращает true, если уведомление действительно ушло — по нему
  /// проверяются правила, а не работа системного лотка.
  static Future<bool> show(WesiNotification notification) async {
    if (wasSeen(notification.id)) return false;

    // Отпечаток запоминается в любом случае, даже когда показывать нельзя.
    // Иначе выключенный вид уведомлений копил бы «непоказанное», и после
    // включения человек получил бы всё разом за неделю.
    markSeen([notification.id]);

    if (!enabled || !kindEnabled(notification.kind)) return false;

    await init();
    final backend = _backend;
    if (backend == null || !_ready) return false;

    try {
      await backend.show(notification);
    } catch (_) {
      return false;
    }
    last.value = notification;
    return true;
  }

  /// Только для тестов.
  @visibleForTesting
  static void reset() {
    _backend = null;
    _ready = false;
    _seenCache = <String>{};
    last.value = null;
  }
}

/// Android: канал уведомлений и разрешение, которое с 13-й версии спрашивают.
class _MobileBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _details =
      AndroidNotificationDetails(
    'wesios_main',
    'WesiOS',
    channelDescription: 'Сроки, платежи, сообщения и обновления',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  @override
  Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    // С Android 13 разрешение спрашивают явно. Отказ — не ошибка:
    // уведомлений просто не будет, а приложение работает как работало.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> show(WesiNotification notification) => _plugin.show(
        notification.id.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(android: _details),
        payload: notification.route,
      );
}

/// Windows, macOS, Linux: системный «тост».
class _DesktopBackend implements NotificationBackend {
  @override
  Future<void> init() async {
    // Windows показывает тост только приложению с ярлыком в меню «Пуск»:
    // по нему система узнаёт, от кого уведомление. Библиотека создаёт его
    // сама, но об этом надо попросить.
    await localNotifier.setup(
      appName: 'WesiOS',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  @override
  Future<void> show(WesiNotification notification) async {
    final toast = LocalNotification(
      title: notification.title,
      body: notification.body,
    );
    await toast.show();
  }
}
