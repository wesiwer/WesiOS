import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/feedback/wesi_feedback.dart';
import '../../../core/notifications/wesi_notifications.dart';
import '../../team/services/team_service.dart';
import '../runtime/wesi_ai_answer_attention.dart';

/// Глобальная плашка «ответ готов» и точка обработки notification deep-links.
/// Живёт поверх всего WesiOS, поэтому не зависит от того, в какой модуль
/// пользователь ушёл, пока Wesi AI продолжал работу.
class WesiAiAnswerReadyHost extends StatefulWidget {
  const WesiAiAnswerReadyHost({
    super.key,
    required this.navigatorKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<WesiAiAnswerReadyHost> createState() => _WesiAiAnswerReadyHostState();
}

class _WesiAiAnswerReadyHostState extends State<WesiAiAnswerReadyHost> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WesiNotifications.routeRequest.addListener(_notificationRouteChanged);
    TeamService.revision.addListener(_employeeSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainNotificationRoute());
  }

  @override
  void dispose() {
    WesiNotifications.routeRequest.removeListener(_notificationRouteChanged);
    TeamService.revision.removeListener(_employeeSessionChanged);
    super.dispose();
  }

  void _employeeSessionChanged() {
    final event = WesiAiAnswerAttention.banner.value;
    if (event != null && !WesiAiAnswerAttention.belongsToCurrentEmployee(event)) {
      WesiAiAnswerAttention.dismiss(event);
    }
  }

  void _notificationRouteChanged() {
    if (!mounted || WesiNotifications.routeRequest.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainNotificationRoute());
  }

  void _drainNotificationRoute() {
    final route = WesiNotifications.takeRouteRequest();
    if (route == null) return;
    unawaited(_openRoute(route));
  }

  Future<void> _openRoute(String route) async {
    if (_opening) return;
    _opening = true;
    try {
      final uri = Uri.tryParse(route);
      final path = uri?.path ?? route;
      if (path == '/ai') {
        final conversation = WesiAiAnswerAttention.conversationFromRoute(route);
        if (conversation != null) {
          await WesiAiAnswerAttention.prepareConversation(conversation);
        }
        final event = WesiAiAnswerAttention.banner.value;
        if (event != null) WesiAiAnswerAttention.dismiss(event);
      }

      NavigatorState? navigator;
      for (var attempt = 0; attempt < 6 && mounted; attempt++) {
        navigator = widget.navigatorKey.currentState;
        if (navigator != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      if (!mounted || navigator == null || path.isEmpty) return;
      navigator.pushNamed(path);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WesiAiAnswerReady?>(
      valueListenable: WesiAiAnswerAttention.banner,
      builder: (context, event, _) {
        final visibleEvent = event != null &&
                WesiAiAnswerAttention.belongsToCurrentEmployee(event)
            ? event
            : null;
        return Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                reverseDuration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  final scale = Tween<double>(begin: 0.88, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeIn,
                    ),
                  );
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: scale, child: child),
                  );
                },
                child: visibleEvent == null
                    ? const SizedBox.shrink(key: ValueKey<String>('ai-ready-empty'))
                    : ConstrainedBox(
                        key: ValueKey<String>(
                          'ai-ready-${visibleEvent.conversationId}-${visibleEvent.completedAt.microsecondsSinceEpoch}',
                        ),
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _AnswerReadyCard(
                          event: visibleEvent,
                          onOpen: () {
                            WesiFeedback.tap();
                            WesiAiAnswerAttention.dismiss(visibleEvent);
                            unawaited(_openRoute(visibleEvent.route));
                          },
                          onDismiss: () {
                            WesiFeedback.tap();
                            WesiAiAnswerAttention.dismiss(visibleEvent);
                          },
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnswerReadyCard extends StatelessWidget {
  const _AnswerReadyCard({
    required this.event,
    required this.onOpen,
    required this.onDismiss,
  });

  final WesiAiAnswerReady event;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      elevation: 16,
      color: colors.surface,
      shadowColor: Colors.black.withOpacity(0.28),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 8, 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ответ готов · ${event.personaLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.preview.isEmpty
                          ? event.conversationTitle
                          : event.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Нажмите, чтобы перейти в диалог',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
