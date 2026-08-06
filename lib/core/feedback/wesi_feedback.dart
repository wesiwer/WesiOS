import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'wesi_haptics.dart';

/// Что именно произошло. Не «какой звук играть» — от этого зависит и звук,
/// и вибрация, и они разные на разных платформах.
enum FeedbackKind {
  /// Обычное нажатие.
  tap,

  /// Выбор из нескольких: вкладка, переключатель, пункт списка.
  select,

  /// Получилось: сохранено, отправлено, выполнено.
  success,

  /// Внимание: удаление, необратимое действие, предупреждение.
  warning,

  /// Не получилось.
  error,

  /// Сообщение ушло.
  send,

  /// Что-то пришло.
  receive,

  /// Уведомление, на которое стоит обернуться.
  notify,
}

/// Отклик на действие: вибрация на телефоне, звук на компьютере.
///
/// **Почему одно место, а не `HapticFeedback` по коду.** Отклик — это не
/// украшение, а обещание: если нажатие иногда отзывается, а иногда нет,
/// человек перестаёт понимать, сработало ли вообще. Разбросанные по экранам
/// вызовы неизбежно расходятся — где-то забыли, где-то поставили не тот.
/// Здесь один список событий и одна таблица соответствий.
///
/// **Почему на телефоне вибрация, а на компьютере звук.** Телефон человек
/// держит в руке, и вибрация — единственный отклик, который не мешает
/// окружающим. У компьютера нет вибромотора, зато есть колонки, а рука на
/// мыши ничего не почувствует. Делать наоборот бессмысленно: телефон,
/// пищащий на каждое нажатие, выключают в первый же день.
///
/// **Почему всё выключается.** Любой отклик кому-то мешает — в тишине, на
/// совещании, просто по вкусу. Настройка, которой нет, приводит к тому, что
/// выключают приложение.
class WesiFeedback {
  const WesiFeedback._();

  static const String _box = 'wesios_settings';
  static const String _hapticsKey = 'feedback_haptics';
  static const String _soundKey = 'feedback_sound';

  /// Меняется при переключении — экраны настроек перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Проигрыватель один на всё приложение.
  ///
  /// Отдельный на каждый звук означал бы новый поток на каждое нажатие;
  /// на сотне нажатий подряд это слышно как заикание.
  static AudioPlayer? _player;

  /// Куда уходят события вместо платформы. Только для тестов: настоящие
  /// вибрация и звук в тестовой среде недоступны, а проверять надо решение
  /// «звать или не звать», а не работу колонок.
  @visibleForTesting
  static void Function(FeedbackKind kind, bool haptic, bool sound)? sink;

  // ─────────────────────────────────────────────────────────── настройки

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  /// Есть ли на этом устройстве вибромотор, о котором стоит говорить.
  ///
  /// Проверяется платформа, а не наличие мотора: на планшете без него
  /// `HapticFeedback` просто ничего не делает, и это правильное поведение.
  /// А вот показывать переключатель вибрации на настольном компьютере —
  /// врать человеку о возможностях его машины.
  static bool get supportsHaptics {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Стоит ли предлагать звук. На телефоне — нет: звуковой отклик там
  /// либо дублирует системный, либо раздражает соседей в транспорте.
  static bool get supportsSound {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static bool get haptics =>
      supportsHaptics && _open()?.get(_hapticsKey) != false;

  static bool get sound => supportsSound && _open()?.get(_soundKey) != false;

  static Future<void> setHaptics(bool on) async {
    await _open()?.put(_hapticsKey, on);
    revision.value++;
  }

  static Future<void> setSound(bool on) async {
    await _open()?.put(_soundKey, on);
    revision.value++;
    if (!on) await _player?.stop();
  }

  // ─────────────────────────────────────────────────────────── события

  static void tap() => _fire(FeedbackKind.tap);

  static void select() => _fire(FeedbackKind.select);

  static void success() => _fire(FeedbackKind.success);

  static void warning() => _fire(FeedbackKind.warning);

  static void error() => _fire(FeedbackKind.error);

  static void send() => _fire(FeedbackKind.send);

  static void receive() => _fire(FeedbackKind.receive);

  static void notify() => _fire(FeedbackKind.notify);

  /// Общий вход. Ничего не ждёт: отклик, из-за которого подтормаживает
  /// нажатие, хуже отсутствия отклика.
  static void of(FeedbackKind kind) => _fire(kind);

  static void _fire(FeedbackKind kind) {
    final withHaptic = haptics;
    final withSound = sound;

    final test = sink;
    if (test != null) {
      test(kind, withHaptic, withSound);
      return;
    }

    if (withHaptic) _vibrate(kind);
    if (withSound) _play(kind);
  }

  /// Сила отдачи по смыслу события.
  ///
  /// Сначала пробуем точный отклик ([WesiHaptics]): на Android 12+ с
  /// подходящим мотором из примитивов собирается рисунок с интенсивностью —
  /// то, за счёт чего отклик на iPhone ощущается отчётливым, а не тупым
  /// толчком. Не вышло — отдаём штатный `HapticFeedback`.
  ///
  /// Он же остаётся единственным на всём, что старше Android 10, и на iOS,
  /// где и так обслуживается правильными генераторами. Четыре его константы
  /// (`VIRTUAL_KEY`, `KEYBOARD_TAP`, `CONTEXT_CLICK`, `CLOCK_TICK`) не имеют
  /// ни силы, ни длительности — но это лучше, чем ничего.
  static void _vibrate(FeedbackKind kind) {
    unawaited(WesiHaptics.play(kind.name).then((precise) {
      if (!precise) _fallbackVibrate(kind);
    }));
  }

  static void _fallbackVibrate(FeedbackKind kind) {
    switch (kind) {
      case FeedbackKind.tap:
      case FeedbackKind.send:
        HapticFeedback.lightImpact();
      case FeedbackKind.select:
      case FeedbackKind.receive:
        HapticFeedback.selectionClick();
      case FeedbackKind.success:
      case FeedbackKind.warning:
        HapticFeedback.mediumImpact();
      case FeedbackKind.error:
      case FeedbackKind.notify:
        HapticFeedback.heavyImpact();
    }
  }

  static String _asset(FeedbackKind kind) => switch (kind) {
        FeedbackKind.tap => 'audio/tap.wav',
        FeedbackKind.select => 'audio/select.wav',
        FeedbackKind.success => 'audio/success.wav',
        FeedbackKind.warning => 'audio/warning.wav',
        FeedbackKind.error => 'audio/error.wav',
        FeedbackKind.send => 'audio/send.wav',
        FeedbackKind.receive => 'audio/receive.wav',
        FeedbackKind.notify => 'audio/notify.wav',
      };

  static void _play(FeedbackKind kind) {
    final player = _player ??= AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop);
    // Ошибку звука глотаем намеренно: не тот звуковой выход, занятое
    // устройство, отсутствующая звуковая карта на сервере — ни одна из этих
    // причин не повод срывать действие человека.
    unawaited(player
        .play(AssetSource(_asset(kind)), volume: 0.45)
        .catchError((_) {}));
  }

  /// Только для тестов: забыть настройки и подставной приёмник.
  @visibleForTesting
  static void reset() {
    sink = null;
    revision.value = 0;
  }
}
