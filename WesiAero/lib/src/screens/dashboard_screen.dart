import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/gateway_orb.dart';
import '../widgets/glass_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= GatewayTokens.desktopBreakpoint;
        final horizontalPadding = desktop
            ? GatewayTokens.space32
            : GatewayTokens.space16;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            GatewayTokens.space24,
            horizontalPadding,
            GatewayTokens.space32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: GatewayTokens.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DashboardHeader(isDemo: controller.snapshot.isDemo),
                  const SizedBox(height: GatewayTokens.space24),
                  if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _ConnectionHero(
                            maxHeight: 590,
                            compact: false,
                          ),
                        ),
                        const SizedBox(width: GatewayTokens.space16),
                        const Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              _ServerCard(),
                              SizedBox(height: GatewayTokens.space16),
                              _MetricsPanel(twoColumns: true),
                              SizedBox(height: GatewayTokens.space16),
                              _SecurityPanel(),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    const _ConnectionHero(maxHeight: 500, compact: true),
                    const SizedBox(height: GatewayTokens.space16),
                    const _ServerCard(),
                    const SizedBox(height: GatewayTokens.space16),
                    const _MetricsPanel(twoColumns: true),
                    const SizedBox(height: GatewayTokens.space16),
                    const _SecurityPanel(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.isDemo});

  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Приватный маршрут',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: GatewayTokens.space4),
              Text(
                'Wesi Aero защищает весь трафик одним касанием.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (isDemo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: palette.warning.withValues(alpha: 0.34),
              ),
            ),
            child: Text(
              'DEMO',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.warning,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.maxHeight,
    required this.compact,
  });

  final double maxHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final snapshot = controller.snapshot;
    final palette = context.palette;
    final activeColor = switch (snapshot.status) {
      TunnelStatus.connected => palette.connected,
      TunnelStatus.error => palette.danger,
      TunnelStatus.disconnecting => palette.warning,
      _ => palette.accent,
    };

    final title = switch (snapshot.status) {
      TunnelStatus.disconnected => 'Wesi Aero отключён',
      TunnelStatus.connecting => 'Создаём защищённый маршрут',
      TunnelStatus.connected => 'Соединение защищено',
      TunnelStatus.disconnecting => 'Завершаем сессию',
      TunnelStatus.error => 'Не удалось подключиться',
    };
    final subtitle = switch (snapshot.status) {
      TunnelStatus.disconnected => 'Нажмите, чтобы открыть защищённый маршрут',
      TunnelStatus.connecting => 'Проверяем ключи и поднимаем туннель',
      TunnelStatus.connected =>
        '${snapshot.protocol.title} · ${snapshot.node?.label ?? 'Автовыбор'}',
      TunnelStatus.disconnecting => 'Kill Switch удерживает трафик до завершения',
      TunnelStatus.error => snapshot.errorMessage ?? 'Повторите попытку',
    };

    return GlassCard(
      padding: EdgeInsets.zero,
      radius: GatewayTokens.radiusHero,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 455 : maxHeight),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.04),
                      radius: 0.78,
                      colors: [
                        activeColor.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GatewayTokens.space24,
                vertical: GatewayTokens.space32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: GatewayTokens.normal,
                    child: Row(
                      key: ValueKey(snapshot.status),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.65),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: GatewayTokens.space8),
                        Text(
                          title.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: activeColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.25,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: GatewayTokens.space16),
                  GatewayOrb(
                    status: snapshot.status,
                    onPressed: controller.isBusy
                        ? null
                        : controller.toggleConnection,
                    size: compact ? 246 : 292,
                    reducedMotion: controller.reducedMotion,
                  ),
                  const SizedBox(height: GatewayTokens.space12),
                  AnimatedSwitcher(
                    duration: GatewayTokens.normal,
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (snapshot.status == TunnelStatus.connected &&
                      snapshot.stats.connectedAt != null) ...[
                    const SizedBox(height: GatewayTokens.space8),
                    Text(
                      formatDuration(
                        DateTime.now().difference(snapshot.stats.connectedAt!),
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final node = controller.selectedNode;
    final palette = context.palette;

    return GlassCard(
      onTap: controller.isConnected || controller.isBusy
          ? null
          : () => controller.selectNavigation(1),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceRaised.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
              border: Border.all(color: palette.border),
            ),
            child: Text(node?.flagEmoji ?? '🌐', style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node?.label ?? 'Сервер не выбран',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: GatewayTokens.space4),
                Text(
                  node == null
                      ? 'Выберите доступный узел'
                      : '${node.pingMs} ms · нагрузка ${(node.load * 100).round()}%',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: GatewayTokens.space8),
          Icon(Icons.chevron_right_rounded, color: palette.textMuted),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.twoColumns});

  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    final stats = GatewayScope.of(context).snapshot.stats;
    return GridView.count(
      crossAxisCount: twoColumns ? 2 : 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: GatewayTokens.space12,
      crossAxisSpacing: GatewayTokens.space12,
      childAspectRatio: 1.55,
      children: [
        _MetricCard(
          icon: Icons.south_rounded,
          label: 'Загрузка',
          value: '${formatBytes(stats.downloadBytesPerSecond)}/s',
        ),
        _MetricCard(
          icon: Icons.north_rounded,
          label: 'Отдача',
          value: '${formatBytes(stats.uploadBytesPerSecond)}/s',
        ),
        _MetricCard(
          icon: Icons.data_usage_rounded,
          label: 'За сессию',
          value: formatBytes(stats.totalBytes),
        ),
        _MetricCard(
          icon: Icons.network_ping_rounded,
          label: 'Задержка',
          value: stats.pingMs == null ? '—' : '${stats.pingMs} ms',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(GatewayTokens.space12),
      radius: GatewayTokens.radiusMedium,
      blur: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: palette.accent),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel();

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final palette = context.palette;
    return GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.connected.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GatewayTokens.radiusSmall),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: palette.connected,
                  size: 22,
                ),
              ),
              const SizedBox(width: GatewayTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kill Switch', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      controller.killSwitch
                          ? 'Утечки при разрыве заблокированы'
                          : 'Защита от утечек отключена',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.killSwitch,
                onChanged: controller.isBusy ? null : controller.setKillSwitch,
              ),
            ],
          ),
          const SizedBox(height: GatewayTokens.space12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: GatewayTokens.space12),
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: palette.textMuted),
              const SizedBox(width: GatewayTokens.space8),
              Expanded(
                child: Text(
                  controller.splitMode.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                controller.protocol.title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.accent,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
