import 'dart:async';

import '../../features/chats/models/chat_message.dart';
import '../../features/chats/services/chat_service.dart';
import '../../features/chats/services/message_store.dart';
import '../../features/home/services/alert_service.dart';
import '../../features/home/widgets/alerts_sheet.dart';
import '../../features/team/services/team_service.dart';
import '../localization/wesi_locale.dart';
import '../services/app_update_service.dart';
import '../services/email_notification_service.dart';
import '../sync/sync_endpoint.dart';
import '../sync/sync_engine.dart';
import '../feedback/wesi_feedback.dart';
import 'wesi_notifications.dart';

/// Кто и по какому поводу поднимает уведомление.
///
/// **Почему поводы не заводятся заново.** Всё, о чём стоит сообщить, уже
/// считается: просрочки, сроки, ближайшие списания, минус на счету,
/// необычные операции, отсутствующая защита и вышедшее обновление — это
/// [AlertService], тот же список, что в колокольчике на главной. Второй
/// набор правил рядом с первым разошёлся бы с ним за неделю, и человек
/// получал бы уведомление о том, чего в колокольчике нет.
///
/// Сюда добавлены только те два повода, которых в колокольчике нет по
/// смыслу: пришедшее сообщение и сорвавшийся обмен с сервером.
///
/// **Почему при запуске тихо.** См. [WesiNotifications.markSeen]: на старте
/// состояние уже накоплено, и показывать его пачкой — способ добиться, чтобы
/// уведомления выключили навсегда.
class NotificationWatcher {
  const NotificationWatcher._();

  static bool _running = false;
  static Timer? _debounce;

  /// Склейка частых изменений.
  ///
  /// Одно действие человека — почти никогда одна запись: сохранение операции
  /// трогает и её, и счёт. Считать список поводов на каждую запись значило бы
  /// считать его пять раз подряд там, где хватает одного.
  static const Duration quiet = Duration(milliseconds: 700);

  static void start() {
    if (_running) return;
    _running = true;

    unawaited(EmailNotificationService.flush());
    unawaited(_seedQuietly());

    AlertService.unreadCount.addListener(_schedule);
    AppUpdateService.latest.addListener(_schedule);
    ChatService.revision.addListener(_schedule);
    MessageStore.revision.addListener(_schedule);
    SyncEndpoint.revision.addListener(_onEndpointChanged);
    SyncEngine.lastReport.addListener(_onSyncReport);
  }

  static void stop() {
    if (!_running) return;
    _running = false;
    _debounce?.cancel();
    _debounce = null;
    AlertService.unreadCount.removeListener(_schedule);
    AppUpdateService.latest.removeListener(_schedule);
    ChatService.revision.removeListener(_schedule);
    MessageStore.revision.removeListener(_schedule);
    SyncEndpoint.revision.removeListener(_onEndpointChanged);
    SyncEngine.lastReport.removeListener(_onSyncReport);
  }

  /// Запомнить всё, что есть сейчас, ничего не показывая.
  static Future<void> _seedQuietly() async {
    WesiNotifications.markSeen([
      for (final alert in await AlertsSheet.collect()) _alertId(alert),
      ..._messageIds(),
    ]);
  }

  static void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(quiet, () => unawaited(_run()));
  }

  static Future<void> _run() async {
    await _checkAlerts();
    await _checkMessages();
  }

  // ────────────────────────────────────────────────────────────── поводы

  static String _alertId(Alert alert) => 'alert:${AlertService.idOf(alert)}';

  static Future<void> _checkAlerts() async {
    for (final alert in await AlertsSheet.collect()) {
      final id = _alertId(alert);
      if (WesiNotifications.wasSeen(id)) continue;
      // Обновление — отдельный вид: его выключают отдельно от сроков.
      final kind = alert.route == '/settings'
          ? NotifyKind.update
          : NotifyKind.alert;
      await _raise(WesiNotification(
        id: id,
        title: alert.title,
        body: alert.detail,
        kind: kind,
        route: alert.route,
      ));
    }
  }

  /// Последние сообщения по каждому разговору.
  ///
  /// Берётся именно последнее, а не все непрочитанные: если пока телефон
  /// лежал в кармане пришло двадцать сообщений, двадцать уведомлений подряд
  /// — это не забота, а наказание.
  static List<String> _messageIds() {
    final ids = <String>[];
    for (final chat in ChatService.all()) {
      final last = MessageStore.lastOf(chat.id);
      if (last != null) ids.add('msg:${last.id}');
    }
    return ids;
  }

  static Future<void> _checkMessages() async {
    final me = TeamService.current?.id;
    final ru = WesiLocale.isRussian;

    for (final chat in ChatService.all()) {
      final message = MessageStore.lastOf(chat.id);
      if (message == null) continue;

      final id = 'msg:${message.id}';
      if (WesiNotifications.wasSeen(id)) continue;

      // О собственных сообщениях не сообщают. Это не мелочь: почти всё, что
      // появляется в переписке на этом устройстве, написано отсюда же.
      if (me != null && message.authorId == me) {
        WesiNotifications.markSeen([id]);
        continue;
      }

      await _raise(WesiNotification(
        id: id,
        title: chat.title,
        body: _preview(message, ru),
        kind: NotifyKind.message,
        route: '/chats',
      ));
    }
  }

  /// Текст в уведомлении. Стикер и файл показываются словами: у них в теле
  /// лежит не текст, а служебная строка.
  static String _preview(ChatMessage message, bool ru) => switch (message.kind) {
        MessageKind.sticker => ru ? 'Стикер' : 'Sticker',
        MessageKind.file => ru ? 'Файл' : 'File',
        _ => message.body,
      };

  static SyncReport? _lastReported;

  /// Новая/обновлённая серверная сессия должна сразу разблокировать очередь
  /// писем, не дожидаясь следующего полного цикла синхронизации.
  static void _onEndpointChanged() {
    if (SyncEndpoint.isConnected) {
      unawaited(EmailNotificationService.flush());
    }
  }

  static void _onSyncReport() {
    final report = SyncEngine.lastReport.value;
    if (report == null) return;
    if (report.ok) {
      _lastReported = null;
      unawaited(EmailNotificationService.flush());
      return;
    }
    // Один и тот же отказ повторяется каждые две минуты, пока не появится
    // связь. Сообщать о нём каждые две минуты — значит сообщать ни о чём.
    final failure = report.firstFailure;
    if (failure == null) return;
    if (_lastReported?.firstFailure?.code == failure.code) return;
    _lastReported = report;

    final ru = WesiLocale.isRussian;
    unawaited(_raise(WesiNotification(
      id: 'sync:${failure.code}:${report.at.day}',
      title: ru ? 'Обмен не прошёл' : 'Sync failed',
      body: failure.describe(russian: ru),
      kind: NotifyKind.sync,
      route: '/settings',
    )));
  }

  static Future<void> _raise(WesiNotification notification) async {
    // Email-дублирование начинается сразу и независимо от разрешения ОС на
    // локальные уведомления. Outbox сохраняет событие до попытки доставки.
    final email = EmailNotificationService.enqueue(notification);
    final shown = await WesiNotifications.show(notification);
    // Звук и вибрация — только вместе с настоящим уведомлением. Отдельно
    // они означали бы «что-то произошло, но что — не скажем».
    if (shown) WesiFeedback.notify();
    await email;
  }

  /// Только для тестов.
  static void reset() {
    stop();
    _lastReported = null;
  }
}
