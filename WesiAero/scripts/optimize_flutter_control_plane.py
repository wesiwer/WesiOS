#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/src/state/gateway_controller.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


def main() -> None:
    text = TARGET.read_text(encoding="utf-8")

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

    TARGET.write_text(text, encoding="utf-8")
    required = [
        "const Duration(seconds: 60)",
        "if (isConnected || isBusy) return;",
        "if (changed || clearedError) notifyListeners();",
        "if (license?.isActive != true) unawaited(refreshQuote());",
    ]
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit(f"Flutter control-plane optimization incomplete: {missing}")
    print("Optimized Flutter control-plane wakeups without changing visuals")


if __name__ == "__main__":
    main()
