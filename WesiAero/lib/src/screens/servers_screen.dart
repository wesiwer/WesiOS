import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/glass_card.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final query = _search.text.trim().toLowerCase();
    final nodes = controller.nodes.where((node) {
      if (query.isEmpty) return true;
      return node.city.toLowerCase().contains(query) ||
          node.country.toLowerCase().contains(query) ||
          node.endpoint.toLowerCase().contains(query);
    }).toList(growable: false);

    final bodyCount = controller.loadingNodes || nodes.isEmpty ? 1 : nodes.length;

    // Build only visible server cards. A Column inside SingleChildScrollView
    // eagerly instantiated every glass/blur card, which scales poorly as the
    // fleet grows. ListView.builder keeps the exact card visuals while
    // virtualising off-screen nodes.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        GatewayTokens.space16,
        GatewayTokens.space24,
        GatewayTokens.space16,
        GatewayTokens.space32,
      ),
      itemCount: 1 + bodyCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading(
                    title: 'Серверные узлы',
                    subtitle: 'Выберите маршрут вручную или оставьте рекомендованный.',
                  ),
                  const SizedBox(height: GatewayTokens.space24),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Город, страна или адрес',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: GatewayTokens.space16),
                ],
              ),
            ),
          );
        }

        if (controller.loadingNodes) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(GatewayTokens.space48),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (nodes.isEmpty) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: const _EmptyServers(),
            ),
          );
        }

        final node = nodes[index - 1];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.only(bottom: GatewayTokens.space12),
              child: _NodeCard(
                node: node,
                selected: controller.selectedNode?.id == node.id,
                enabled: !controller.isConnected && !controller.isBusy,
                onSelect: () {
                  controller.selectNode(node);
                  controller.selectNavigation(0);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final GatewayNode node;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: GatewayTokens.normal,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GatewayTokens.radiusLarge),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.12),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: GlassCard(
        onTap: enabled ? onSelect : null,
        color: selected
            ? palette.accent.withValues(alpha: 0.10)
            : palette.glass,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceRaised.withValues(alpha: 0.64),
                borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
                border: Border.all(color: palette.border),
              ),
              child: Text(node.flagEmoji, style: const TextStyle(fontSize: 25)),
            ),
            const SizedBox(width: GatewayTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: GatewayTokens.space8,
                    runSpacing: GatewayTokens.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(node.label, style: Theme.of(context).textTheme.titleMedium),
                      if (node.recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: palette.connected.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'РЕКОМЕНДОВАНО',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: palette.connected,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: GatewayTokens.space8),
                  Wrap(
                    spacing: GatewayTokens.space12,
                    runSpacing: GatewayTokens.space4,
                    children: [
                      _InlineMetric(
                        icon: Icons.network_ping_rounded,
                        text: '${node.pingMs} ms',
                      ),
                      _InlineMetric(
                        icon: Icons.donut_large_rounded,
                        text: '${(node.load * 100).round()}% загрузки',
                      ),
                      _InlineMetric(
                        icon: Icons.shield_outlined,
                        text: node.protocols.length > 1
                            ? '${node.protocols.length} протокола'
                            : node.protocols.isEmpty
                                ? 'Нет протокола'
                                : node.protocols.first.title,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: GatewayTokens.space8),
            AnimatedContainer(
              duration: GatewayTokens.normal,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? palette.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? palette.accent : palette.border,
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: palette.accentForeground,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: context.palette.textMuted),
        const SizedBox(width: GatewayTokens.space4),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(GatewayTokens.space24),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.public_off_rounded,
                size: 34,
                color: context.palette.textMuted,
              ),
              const SizedBox(height: GatewayTokens.space12),
              Text(
                'Узлы не найдены',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: GatewayTokens.space4),
              Text(
                'Измените запрос или проверьте доступ к control plane.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
