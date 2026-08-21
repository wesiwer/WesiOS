#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "lib/src/state/gateway_controller.dart"
DASHBOARD = ROOT / "lib/src/screens/dashboard_screen.dart"
APP_SHELL = ROOT / "lib/src/screens/app_shell.dart"
AMBIENT = ROOT / "lib/src/widgets/ambient_background.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


def optimize_controller() -> None:
    text = CONTROLLER.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "    _catalogTimer = Timer.periodic(\n"
        "      const Duration(seconds: 20),\n"
        "      (_) => unawaited(syncCatalog(quiet: true)),\n"
        "    );\n",
        "    _catalogTimer = Timer.periodic(\n"
        "      const Duration(seconds: 60),\n"
        "      (_) {\n"
        "        // Do not compete with the UI/native tunnel while a session is\n"
        "        // active. The catalog is configuration, not live telemetry.\n"
        "        if (isConnected || isBusy) return;\n"
        "        unawaited(syncCatalog(quiet: true));\n"
        "      },\n"
        "    );\n",
        "catalog timer",
    )

    old_sync = '''  Future<void> syncCatalog({bool quiet = false}) async {
    try {
      final next = await _commerce.fetchCatalog();
      if (catalog?.revision != next.revision) {
        catalog = next;
        selectedPlan = next.plans.cast<TariffPlan?>().firstWhere(
              (item) => item?.id == selectedPlan?.id,
              orElse: () => next.plans.isEmpty ? null : next.plans.first,
            );
        if (next.servers.isNotEmpty) {
          final selectedId = selectedNode?.id;
          nodes = next.servers;
          selectedNode = nodes.cast<GatewayNode?>().firstWhere(
                (item) => item?.id == selectedId,
                orElse: () => nodes.cast<GatewayNode?>().firstWhere(
                      (item) => item?.recommended == true,
                      orElse: () => nodes.first,
                    ),
              );
        }
        unawaited(refreshQuote());
      }
      commerceError = null;
      notifyListeners();
    } catch (error) {
      if (!quiet) {
        commerceError = _friendlyCommerceError(error);
        notifyListeners();
      }
    }
  }
'''
    new_sync = '''  Future<void> syncCatalog({bool quiet = false}) async {
    try {
      final next = await _commerce.fetchCatalog();
      final changed = catalog?.revision != next.revision;
      final clearedError = commerceError != null;
      if (changed) {
        catalog = next;
        selectedPlan = next.plans.cast<TariffPlan?>().firstWhere(
              (item) => item?.id == selectedPlan?.id,
              orElse: () => next.plans.isEmpty ? null : next.plans.first,
            );
        if (next.servers.isNotEmpty) {
          final selectedId = selectedNode?.id;
          nodes = next.servers;
          selectedNode = nodes.cast<GatewayNode?>().firstWhere(
                (item) => item?.id == selectedId,
                orElse: () => nodes.cast<GatewayNode?>().firstWhere(
                      (item) => item?.recommended == true,
                      orElse: () => nodes.first,
                    ),
              );
        }
        // Pricing is irrelevant once a live prototype/production license is
        // active, so avoid another network/decode cycle in the main shell.
        if (license?.isActive != true) unawaited(refreshQuote());
      }
      commerceError = null;
      if (changed || clearedError) notifyListeners();
    } catch (error) {
      if (!quiet) {
        final nextError = _friendlyCommerceError(error);
        if (commerceError != nextError) {
          commerceError = nextError;
          notifyListeners();
        }
      }
    }
  }
'''
    text = replace_once(text, old_sync, new_sync, "quiet catalog sync")
    CONTROLLER.write_text(text, encoding="utf-8")


def optimize_dashboard() -> None:
    text = DASHBOARD.read_text(encoding="utf-8")
    old_metrics = '''class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.twoColumns});

  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<SessionStats>(
        valueListenable: GatewayTelemetry.stats,
        builder: (context, stats, _) {
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
        },
      ),
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
'''
    new_metrics = '''class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.twoColumns});

  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GridView.count(
        crossAxisCount: twoColumns ? 2 : 1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: GatewayTokens.space12,
        crossAxisSpacing: GatewayTokens.space12,
        childAspectRatio: 1.55,
        children: const [
          _MetricCard(
            icon: Icons.south_rounded,
            label: 'Загрузка',
            kind: _MetricKind.download,
          ),
          _MetricCard(
            icon: Icons.north_rounded,
            label: 'Отдача',
            kind: _MetricKind.upload,
          ),
          _MetricCard(
            icon: Icons.data_usage_rounded,
            label: 'За сессию',
            kind: _MetricKind.total,
          ),
          _MetricCard(
            icon: Icons.network_ping_rounded,
            label: 'Задержка',
            kind: _MetricKind.ping,
          ),
        ],
      ),
    );
  }
}

enum _MetricKind { download, upload, total, ping }

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.kind,
  });

  final IconData icon;
  final String label;
  final _MetricKind kind;

  String _value(SessionStats stats) => switch (kind) {
        _MetricKind.download =>
          '${formatBytes(stats.downloadBytesPerSecond)}/s',
        _MetricKind.upload => '${formatBytes(stats.uploadBytesPerSecond)}/s',
        _MetricKind.total => formatBytes(stats.totalBytes),
        _MetricKind.ping => stats.pingMs == null ? '—' : '${stats.pingMs} ms',
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(GatewayTokens.space12),
      radius: GatewayTokens.radiusMedium,
      blur: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: palette.accent),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<SessionStats>(
                valueListenable: GatewayTelemetry.stats,
                builder: (context, stats, _) => Text(
                  _value(stats),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
'''
    text = replace_once(text, old_metrics, new_metrics, "dashboard telemetry isolation")
    text = replace_once(
        text,
        "onPressed: controller.isBusy\n                          ? null\n                          : controller.toggleConnection,",
        "onPressed: controller.isBusy || controller.commerceLoading\n                          ? null\n                          : controller.toggleConnection,",
        "disable connect during initialization",
    )
    DASHBOARD.write_text(text, encoding="utf-8")


def optimize_backdrop_group() -> None:
    text = APP_SHELL.read_text(encoding="utf-8")
    if "child: BackdropGroup(" not in text:
        text = replace_once(
            text,
            "      child: SafeArea(\n        bottom: false,",
            "      child: BackdropGroup(\n        child: SafeArea(\n          bottom: false,",
            "BackdropGroup opening",
        )
        text = replace_once(
            text,
            "          },\n        ),\n      ),\n    );\n  }\n}",
            "          },\n        ),\n      ),\n      ),\n    );\n  }\n}",
            "BackdropGroup closing",
        )
    APP_SHELL.write_text(text, encoding="utf-8")


def optimize_ambient_background() -> None:
    text = AMBIENT.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  late final AnimationController _controller;\n  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;",
        "  late final AnimationController _controller;\n"
        "  late final ValueNotifier<double> _glowPhase;\n"
        "  Duration _lastGlowFrame = Duration.zero;\n"
        "  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;",
        "ambient sampled phase fields",
    )
    text = replace_once(
        text,
        "    _controller = AnimationController(\n"
        "      vsync: this,\n"
        "      duration: const Duration(seconds: 18),\n"
        "    );\n"
        "    _syncTicker();",
        "    _controller = AnimationController(\n"
        "      vsync: this,\n"
        "      duration: const Duration(seconds: 18),\n"
        "    );\n"
        "    _glowPhase = ValueNotifier<double>(_controller.value);\n"
        "    _controller.addListener(_sampleGlowFrame);\n"
        "    _syncTicker();",
        "ambient phase initialization",
    )
    text = replace_once(
        text,
        "  void _syncTicker() {",
        "  void _sampleGlowFrame() {\n"
        "    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;\n"
        "    if (elapsed < _lastGlowFrame) _lastGlowFrame = Duration.zero;\n"
        "    if (_controller.isAnimating &&\n"
        "        elapsed - _lastGlowFrame < const Duration(milliseconds: 33)) {\n"
        "      return;\n"
        "    }\n"
        "    _lastGlowFrame = elapsed;\n"
        "    final next = _controller.value;\n"
        "    if (_glowPhase.value != next) _glowPhase.value = next;\n"
        "  }\n\n"
        "  void _syncTicker() {",
        "ambient 30fps sampling",
    )
    text = replace_once(
        text,
        "    WidgetsBinding.instance.removeObserver(this);\n"
        "    _controller.dispose();\n"
        "    super.dispose();",
        "    WidgetsBinding.instance.removeObserver(this);\n"
        "    _controller.removeListener(_sampleGlowFrame);\n"
        "    _controller.dispose();\n"
        "    _glowPhase.dispose();\n"
        "    super.dispose();",
        "ambient phase disposal",
    )
    text = replace_once(
        text,
        "                animation: _controller,",
        "                phase: _glowPhase,",
        "ambient painter phase argument",
    )
    text = replace_once(
        text,
        "    required this.animation,\n"
        "    required this.accent,",
        "    required this.phase,\n"
        "    required this.accent,",
        "ambient painter constructor",
    )
    text = replace_once(
        text,
        "  }) : super(repaint: animation);\n\n"
        "  final Animation<double> animation;",
        "  }) : super(repaint: phase);\n\n"
        "  final ValueListenable<double> phase;",
        "ambient painter listenable",
    )
    text = replace_once(
        text,
        "    final angle = animation.value * math.pi * 2;",
        "    final angle = phase.value * math.pi * 2;",
        "ambient sampled angle",
    )
    text = replace_once(
        text,
        "    return oldDelegate.animation != animation ||\n"
        "        oldDelegate.accent != accent ||",
        "    return oldDelegate.phase != phase ||\n"
        "        oldDelegate.accent != accent ||",
        "ambient shouldRepaint",
    )
    AMBIENT.write_text(text, encoding="utf-8")


def main() -> None:
    optimize_controller()
    optimize_dashboard()
    optimize_backdrop_group()
    optimize_ambient_background()

    controller = CONTROLLER.read_text(encoding="utf-8")
    dashboard = DASHBOARD.read_text(encoding="utf-8")
    shell = APP_SHELL.read_text(encoding="utf-8")
    ambient = AMBIENT.read_text(encoding="utf-8")
    required = [
        (controller, "const Duration(seconds: 60)"),
        (controller, "if (isConnected || isBusy) return;"),
        (controller, "if (changed || clearedError) notifyListeners();"),
        (controller, "if (license?.isActive != true) unawaited(refreshQuote());"),
        (dashboard, "enum _MetricKind { download, upload, total, ping }"),
        (dashboard, "blur: 18"),
        (dashboard, "controller.isBusy || controller.commerceLoading"),
        (shell, "child: BackdropGroup("),
        (ambient, "const Duration(milliseconds: 33)"),
        (ambient, "phase: _glowPhase"),
    ]
    missing = [marker for source, marker in required if marker not in source]
    if missing:
        raise SystemExit(f"Flutter runtime optimization incomplete: {missing}")
    print(
        "Optimized control-plane wakeups, telemetry rebuilds, grouped glass blur "
        "and ambient GPU cadence without removing visual effects"
    )


if __name__ == "__main__":
    main()
