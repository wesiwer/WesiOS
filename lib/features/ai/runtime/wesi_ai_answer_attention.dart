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

  static bool _chatRouteCurrent = false;

  /// Observer подключается к корневому Navigator. В отличие от dispose
  /// контроллера он видит и случай, когда /ai остаётся живым под другим route.
  static final NavigatorObserver navigatorObserver = _WesiAiNavigatorObserver();

  static bool get chatVisible => _chatRouteCurrent;

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
    bool? chatVisible,
  }) async {
    final foreground = _foreground;
    final delivery = deliveryFor(
      foreground: foreground,
      chatVisible: chatVisible ?? _chatRouteCurrent,
    );

    // В foreground даём один узнаваемый Wesi haptic/sound ровно на
    // thinking -> ready. В background сигнал отдаёт сама ОС вместе с
    // системным notification, иначе некоторые устройства вибрируют дважды.
    if (foreground) WesiFeedback.notify();

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
          body: 'Ответ готов в «${event.conversationTitle}». Нажмите, чтобы открыть диалог.',
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

  static void _routeChanged(Route<dynamic>? route) {
    _chatRouteCurrent = route?.settings.name == '/ai';
  }

  @visibleForTesting
  static void reset() {
    banner.value = null;
    sink = null;
    _chatRouteCurrent = false;
  }
}

class _WesiAiNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WesiAiAnswerAttention._routeChanged(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WesiAiAnswerAttention._routeChanged(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    WesiAiAnswerAttention._routeChanged(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WesiAiAnswerAttention._routeChanged(previousRoute);
  }
}
