#!/usr/bin/env python3
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AMBIENT = ROOT / "lib/src/widgets/ambient_background.dart"
VPN_REGRESSION_FIX = ROOT / "scripts/fix_android_vpn_regressions.py"


def main() -> None:
    text = AMBIENT.read_text(encoding="utf-8")
    old = "  final ValueListenable<double> phase;"
    new = "  final ValueNotifier<double> phase;"
    if new not in text:
        if text.count(old) != 1:
            raise SystemExit(
                f"ambient perf compatibility patch expected one anchor, found {text.count(old)}"
            )
        text = text.replace(old, new, 1)
        AMBIENT.write_text(text, encoding="utf-8")
    print("Applied Flutter 3.47 ambient notifier compatibility patch")

    # Live Android workflows already invoke this compatibility step after the
    # generated native VPN code is hardened. Apply the regression guard here so
    # every Live/ARM64 build removes the false Xray startup gate and serializes
    # the Xray -> WireGuard VpnService handoff.
    runpy.run_path(str(VPN_REGRESSION_FIX), run_name="__main__")


if __name__ == "__main__":
    main()
