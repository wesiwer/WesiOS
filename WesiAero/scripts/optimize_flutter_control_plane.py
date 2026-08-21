#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "lib/src/state/gateway_controller.dart"
DASHBOARD = ROOT / "lib/src/screens/dashboard_screen.dart"


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
      blur: 12,
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
    DASHBOARD.write_text(text, encoding="utf-8")


def main() -> None:
    optimize_controller()
    optimize_dashboard()

    controller = CONTROLLER.read_text(encoding="utf-8")
    dashboard = DASHBOARD.read_text(encoding="utf-8")
    required = [
        (controller, "const Duration(seconds: 60)"),
        (controller, "if (isConnected || isBusy) return;"),
        (controller, "if (changed || clearedError) notifyListeners();"),
        (controller, "if (license?.isActive != true) unawaited(refreshQuote());"),
        (dashboard, "enum _MetricKind { download, upload, total, ping }"),
        (dashboard, "ValueListenableBuilder<SessionStats>"),
    ]
    missing = [marker for source, marker in required if marker not in source]
    if missing:
        raise SystemExit(f"Flutter runtime optimization incomplete: {missing}")
    print("Optimized Flutter control-plane wakeups and isolated live telemetry without changing visuals")


if __name__ == "__main__":
    main()
