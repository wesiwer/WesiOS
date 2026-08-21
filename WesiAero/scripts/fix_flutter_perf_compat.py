#!/usr/bin/env python3
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AMBIENT = ROOT / "lib/src/widgets/ambient_background.dart"
VPN_REGRESSION_FIX = ROOT / "scripts/fix_android_vpn_regressions.py"
HEV_TUN_SETUP = ROOT / "scripts/configure_android_hev_tun.py"
HEV_JNI_KEEP = ROOT / "scripts/fix_android_hev_jni_keep.py"


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

    # Live Android workflows invoke this step after generated VPN code is
    # hardened. Keep the lifecycle regression guard, replace Xray's built-in
    # Android TUN with hev-socks5-tunnel, then protect JNI RegisterNatives
    # methods from release/R8 dead-code elimination.
    runpy.run_path(str(VPN_REGRESSION_FIX), run_name="__main__")
    runpy.run_path(str(HEV_TUN_SETUP), run_name="__main__")
    runpy.run_path(str(HEV_JNI_KEEP), run_name="__main__")


if __name__ == "__main__":
    main()
