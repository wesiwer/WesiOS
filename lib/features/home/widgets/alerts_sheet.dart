import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/security/shield_service.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/window_controls.dart';
import '../../tasks/services/task_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../services/alert_service.dart';

/// Колокольчик на главной: сколько сейчас требует внимания.
class AlertsBell extends StatefulWidget {
  /// Размер иконки. По умолчанию 20, на главной делаем крупнее.
  final double size;

  const AlertsBell({super.key, this.size = 20});

  @override
  State<AlertsBell> createState() => _AlertsBellState();
}

class _AlertsBellState extends State<AlertsBell> {
  List<Alert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _load();
    TreasuryService.revision.addListener(_load);
    TaskService.revision.addListener(_load);
    ShieldService.revision.addListener(_load);
    AppUpdateService.latest.addListener(_load);
  }

  @override
  void dispose() {
    TreasuryService.revision.removeListener(_load);
    TaskService.revision.removeListener(_load);
    ShieldService.revision.removeListener(_load);
    AppUpdateService.latest.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final alerts = await AlertsSheet.collect();
    if (mounted) setState(() => _alerts = alerts);
  }

  @override
  Widget build(BuildContext context) {
    final urgent =
        _alerts.where((a) => a.level != AlertLevel.info).length;
    final count = _alerts.length;

    return Tooltip(
      message: WesiLocale.isRussian ? 'Уведомления' : 'Notifications',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await AlertsSheet.show(context, _alerts);
          _load();
        },
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                count == 0
                    ? Icons.notifications_outlined
                    : Icons.notifications_active_outlined,
                size: widget.size,
                color: count == 0 ? AppTheme.textMuted : AppTheme.textPrimary,
              ),
              if (count > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    constraints: BoxConstraints(minWidth: 14),
                    decoration: BoxDecoration(
                      color: urgent > 0
                          ? AppTheme.accentRed
                          : AppTheme.accent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Панель со списком уведомлений.
class AlertsSheet extends StatelessWidget {
  final List<Alert> alerts;

  const AlertsSheet({super.key, required this.alerts});

  static Future<List<Alert>> collect() async {
    try {
      final service = TreasuryService();
      final transactions = await service.getAllTransactions();
      final balance = await service.getCurrentBalance();
      final tasks = await TaskService().getAll();
      final release = AppUpdateService.latest.value;
      return AlertService.compute(
        transactions: transactions,
        tasks: tasks,
        balance: balance,
        now: DateTime.now(),
        russian: WesiLocale.isRussian,
        shieldConfigured: ShieldService.isConfigured,
        updateVersion: release?.version,
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<void> show(BuildContext context, List<Alert> alerts) =>
      showDialog(
        context: context,
        builder: (_) => AlertsSheet(alerts: alerts),
      );

  Color _color(AlertLevel level) => switch (level) {
        AlertLevel.danger => AppTheme.accentRed,
        AlertLevel.warning => AppTheme.accent,
        AlertLevel.info => AppTheme.textSecondary,
      };

  IconData _icon(AlertLevel level) => switch (level) {
        AlertLevel.danger => Icons.error_outline,
        AlertLevel.warning => Icons.warning_amber_outlined,
        AlertLevel.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.fromLTRB(24, kTitleBarHeight + 24, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ru ? 'Уведомления' : 'Notifications',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.glassBorder),
            Flexible(
              child: alerts.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(28),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: AppTheme.accentGreen),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              ru
                                  ? 'Всё спокойно: просроченных задач нет, '
                                      'баланс в плюсе, защита настроена.'
                                  : 'All clear: nothing overdue, balance is '
                                      'positive, protection is on.',
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: alerts.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, color: AppTheme.glassBorder),
                      itemBuilder: (_, i) {
                        final a = alerts[i];
                        return InkWell(
                          onTap: a.route == null
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(context, a.route!);
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 13),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(_icon(a.level),
                                    size: 17, color: _color(a.level)),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.title,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _color(a.level)),
                                      ),
                                      if (a.detail.isNotEmpty) ...[
                                        SizedBox(height: 3),
                                        Text(
                                          a.detail,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              height: 1.35,
                                              color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (a.route != null)
                                  Icon(Icons.chevron_right,
                                      size: 16, color: AppTheme.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
