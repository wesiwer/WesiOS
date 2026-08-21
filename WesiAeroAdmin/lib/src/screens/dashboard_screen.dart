import 'package:flutter/material.dart';

import '../design/admin_theme.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final snapshot = controller.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final counts = snapshot.counts;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Панель управления',
                subtitle: 'Живое состояние Wesi Aero · ревизия ${snapshot.revision}',
                trailing: controller.error == null
                    ? null
                    : Icon(Icons.error_outline_rounded, color: context.palette.danger),
              ),
              const SizedBox(height: GatewayTokens.space24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 900
                      ? (constraints.maxWidth - 48) / 4
                      : constraints.maxWidth >= 560
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                  return Wrap(
                    spacing: GatewayTokens.space16,
                    runSpacing: GatewayTokens.space16,
                    children: [
                      _MetricCard(
                        width: width,
                        icon: Icons.dns_rounded,
                        value: '${counts.serversOnline}/${counts.servers}',
                        label: 'Серверов онлайн',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.key_rounded,
                        value: '${counts.licensesActive}',
                        label: 'Активных ключей',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.devices_rounded,
                        value: '${counts.devices}',
                        label: 'Привязано устройств',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.payments_rounded,
                        value: '${(counts.revenueMinor / 100).toStringAsFixed(0)} ₽',
                        label: 'Подтверждено оплат',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: GatewayTokens.space24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final servers = _StatusList(
                    title: 'Серверы',
                    children: snapshot.servers.take(5).map((server) {
                      return _StatusRow(
                        icon: server.online
                            ? Icons.check_circle_rounded
                            : Icons.cancel_outlined,
                        title: server.displayName,
                        subtitle: '${server.endpoint} · ${(server.load * 100).round()}% load',
                        positive: server.online,
                      );
                    }).toList(growable: false),
                  );
                  final payments = _StatusList(
                    title: 'Последние оплаты',
                    children: snapshot.payments.take(5).map((payment) {
                      return _StatusRow(
                        icon: payment.status == 'paid'
                            ? Icons.verified_rounded
                            : Icons.schedule_rounded,
                        title: '${payment.provider} · ${(payment.amountMinor / 100).toStringAsFixed(0)} ₽',
                        subtitle: '${payment.durationDays} дней · ${payment.deviceLimit} устр.',
                        positive: payment.status == 'paid',
                      );
                    }).toList(growable: false),
                  );
                  if (!wide) {
                    return Column(
                      children: [servers, const SizedBox(height: 16), payments],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: servers),
                      const SizedBox(width: GatewayTokens.space16),
                      Expanded(child: payments),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.palette.connected),
            const SizedBox(height: GatewayTokens.space16),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: GatewayTokens.space12),
            if (children.isEmpty)
              Text('Пока нет данных', style: Theme.of(context).textTheme.bodyMedium)
            else
              ...children,
          ],
        ),
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.positive,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool positive;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          icon,
          color: positive ? context.palette.connected : context.palette.textMuted,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      );
}
