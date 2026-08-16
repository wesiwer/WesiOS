import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/feedback/wesi_feedback.dart';
import '../../../core/notifications/wesi_notifications.dart';
import '../../team/services/team_service.dart';
import '../storage/wesi_ai_local_store.dart';

enum WesiAiAnswerDelivery {
  inChat,
  inAppBanner,
  systemNotification,
}

class WesiAiAnswerReady {
  const WesiAiAnswerReady({
    required this.conversationId,
    required this.conversationTitle,
    required this.personaLabel,
    required this.preview,
    required this.completedAt,
  });

  final String conversationId;
  final String conversationTitle;
  final String personaLabel;
  final String preview;
  final DateTime completedAt;

  String get route => Uri(
        path: '/ai',
        queryParameters: <String, String>{'conversation': conversationId},
      ).toString();
}

/// Единая точка, которая сообщает пользователю, что Wesi AI закончил turn.
///
/// Правила намеренно различаются по состоянию UI:
/// - пользователь уже смотрит этот чат -> только отчётливый тактильный сигнал;
/// - WesiOS открыт, но пользователь ушёл в другой модуль -> внутренняя плашка;
/// - приложение не в foreground -> системное уведомление с deep-link в чат.
class WesiAiAnswerAttention {
  const WesiAiAnswerAttention._();

  static final ValueNotifier<WesiAiAnswerReady?> banner =
      ValueNotifier<WesiAiAnswerReady?>(null);

  @visibleForTesting
  static void Function(WesiAiAnswerReady event, WesiAiAnswerDelivery delivery)?
      sink;

  static WesiAiAnswerDelivery deliveryFor({
    required bool foreground,
    required bool chatVisible,
  }) {
    if (!foreground) return WesiAiAnswerDelivery.systemNotification;
    if (chatVisible) return WesiAiAnswerDelivery.inChat;
    return WesiAiAnswerDelivery.inAppBanner;
  }

  static bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> complete(
    WesiAiAnswerReady event, {
    required bool chatVisible,
  }) async {
    final delivery = deliveryFor(
      foreground: _foreground,
      chatVisible: chatVisible,
    );

    // Один узнаваемый сигнал ровно в момент перехода thinking -> ready.
    // На телефоне это haptic, на desktop — короткий notify sound.
    WesiFeedback.notify();

    final test = sink;
    if (test != null) {
      test(event, delivery);
      return;
    }

    switch (delivery) {
      case WesiAiAnswerDelivery.inChat:
        return;
      case WesiAiAnswerDelivery.inAppBanner:
        banner.value = event;
        return;
      case WesiAiAnswerDelivery.systemNotification:
        await WesiNotifications.show(WesiNotification(
          id: 'wesi-ai:${event.conversationId}:${event.completedAt.microsecondsSinceEpoch}',
          title: 'Wesi AI · ${event.personaLabel}',
          body: event.preview.isEmpty
              ? 'Ответ готов. Нажмите, чтобы открыть диалог.'
              : event.preview,
          kind: NotifyKind.message,
          route: event.route,
        ));
    }
  }

  static void dismiss(WesiAiAnswerReady event) {
    if (identical(banner.value, event) ||
        banner.value?.conversationId == event.conversationId) {
      banner.value = null;
    }
  }

  static String? conversationFromRoute(String? route) {
    final uri = Uri.tryParse((route ?? '').trim());
    if (uri == null || uri.path != '/ai') return null;
    final id = (uri.queryParameters['conversation'] ?? '').trim();
    return id.isEmpty ? null : id;
  }

  /// Перед навигацией фиксирует нужный диалог как active в durable store.
  /// Поэтому deep-link работает даже после пересоздания AI-экрана.
  static Future<bool> prepareConversation(String conversationId) async {
    final employee = TeamService.current;
    final id = conversationId.trim();
    if (employee == null || id.isEmpty) return false;
    try {
      final store = WesiAiLocalStore(employee.id);
      final state = await store.load();
      if (!state.conversations.any((item) => item.id == id)) return false;
      await store.save(state.copyWith(activeConversationId: id));
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void reset() {
    banner.value = null;
    sink = null;
  }
}
