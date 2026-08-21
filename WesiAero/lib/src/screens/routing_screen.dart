import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/glass_card.dart';

class RoutingScreen extends StatelessWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final locked = controller.isConnected || controller.isBusy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        GatewayTokens.space16,
        GatewayTokens.space24,
        GatewayTokens.space16,
        GatewayTokens.space32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Маршрутизация',
                subtitle: locked
                    ? 'Отключите шлюз, чтобы изменить правила.'
                    : 'Определите, какой трафик направлять через туннель.',
                trailing: IconButton.filledTonal(
                  tooltip: 'Добавить правило',
                  onPressed: locked ? null : () => _showAddRule(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              _ModeSelector(enabled: !locked),
              const SizedBox(height: GatewayTokens.space16),
              _RoutingExplanation(mode: controller.splitMode),
              const SizedBox(height: GatewayTokens.space24),
              Text('Правила', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              if (controller.splitMode == SplitMode.allTraffic)
                const _AllTrafficNotice()
              else if (controller.rules.isEmpty)
                const _EmptyRules()
              else
                ...controller.rules.map(
                  (rule) => Padding(
                    padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
                    child: _RuleCard(rule: rule, locked: locked),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddRule(BuildContext context) async {
    final labelController = TextEditingController();
    final valueController = TextEditingController();
    var kind = RoutingRuleKind.application;
    final result = await showDialog<RoutingRuleKind>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Новое правило'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<RoutingRuleKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: const [
                    DropdownMenuItem(
                      value: RoutingRuleKind.application,
                      child: Text('Приложение'),
                    ),
                    DropdownMenuItem(
                      value: RoutingRuleKind.domain,
                      child: Text('Домен'),
                    ),
                    DropdownMenuItem(
                      value: RoutingRuleKind.ipRange,
                      child: Text('IP / CIDR'),
                    ),
                  ],
                  onChanged: (value) => setState(() => kind = value ?? kind),
                ),
                const SizedBox(height: GatewayTokens.space12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: GatewayTokens.space12),
                TextField(
                  controller: valueController,
                  decoration: const InputDecoration(
                    labelText: 'Package, домен или диапазон',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (labelController.text.trim().isEmpty ||
                    valueController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, kind);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    GatewayScope.read(context).addRule(
      label: labelController.text.trim(),
      value: valueController.text.trim(),
      kind: result,
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final cards = SplitMode.values
            .map(
              (mode) => _ModeCard(
                mode: mode,
                selected: controller.splitMode == mode,
                enabled: enabled,
                onTap: () => controller.setSplitMode(mode),
              ),
            )
            .toList(growable: false);
        if (narrow) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last)
                  const SizedBox(height: GatewayTokens.space8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last)
                const SizedBox(width: GatewayTokens.space8),
            ],
          ],
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SplitMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = switch (mode) {
      SplitMode.allTraffic => Icons.all_inclusive_rounded,
      SplitMode.allowlist => Icons.filter_alt_outlined,
      SplitMode.denylist => Icons.filter_alt_off_outlined,
    };
    return GlassCard(
      onTap: enabled ? onTap : null,
      color: selected
          ? palette.accent.withValues(alpha: 0.11)
          : palette.glass,
      padding: const EdgeInsets.all(GatewayTokens.space12),
      radius: GatewayTokens.radiusMedium,
      child: Row(
        children: [
          Icon(icon, color: selected ? palette.accent : palette.textMuted),
          const SizedBox(width: GatewayTokens.space8),
          Expanded(
            child: Text(
              mode.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? palette.accent : palette.textPrimary,
                  ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 18, color: palette.accent),
        ],
      ),
    );
  }
}

class _RoutingExplanation extends StatelessWidget {
  const _RoutingExplanation({required this.mode});

  final SplitMode mode;

  @override
  Widget build(BuildContext context) {
    final text = switch (mode) {
      SplitMode.allTraffic =>
        'Все TCP, UDP и поддерживаемые IP-пакеты устройства идут через шлюз.',
      SplitMode.allowlist =>
        'Только включённые приложения, домены и диапазоны используют шлюз.',
      SplitMode.denylist =>
        'Весь трафик идёт через шлюз, кроме включённых исключений.',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: context.palette.accent),
        const SizedBox(width: GatewayTokens.space8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.locked});

  final RoutingRule rule;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final palette = context.palette;
    final icon = switch (rule.kind) {
      RoutingRuleKind.application => Icons.apps_rounded,
      RoutingRuleKind.domain => Icons.language_rounded,
      RoutingRuleKind.ipRange => Icons.lan_outlined,
    };
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.surfaceRaised.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(GatewayTokens.radiusSmall),
            ),
            child: Icon(icon, size: 21, color: palette.textSecondary),
          ),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  rule.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: locked ? null : () => controller.removeRule(rule.id),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          Switch(
            value: rule.enabled,
            onChanged: locked
                ? null
                : (enabled) => controller.toggleRule(rule.id, enabled),
          ),
        ],
      ),
    );
  }
}

class _AllTrafficNotice extends StatelessWidget {
  const _AllTrafficNotice();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Icon(Icons.route_rounded, color: context.palette.connected),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Text(
              'Дополнительные правила не нужны: установлен маршрут 0.0.0.0/0 и ::/0.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRules extends StatelessWidget {
  const _EmptyRules();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Text(
        'Список пуст. Добавьте приложение, домен или IP-диапазон.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

