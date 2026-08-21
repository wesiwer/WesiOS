#!/usr/bin/env python3
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AMBIENT = ROOT / "lib/src/widgets/ambient_background.dart"
VPN_REGRESSION_FIX = ROOT / "scripts/fix_android_vpn_regressions.py"
HEV_TUN_SETUP = ROOT / "scripts/configure_android_hev_tun.py"
HEV_JNI_KEEP = ROOT / "scripts/fix_android_hev_jni_keep.py"
MULTI_ENGINE_FLUTTER = ROOT / "scripts/apply_multi_engine_profiles.py"
BUILD_SINGBOX = ROOT / "scripts/build_android_singbox.py"
CONFIGURE_SINGBOX = ROOT / "scripts/configure_android_singbox.py"
PATCH_SINGBOX_PROFILES = ROOT / "scripts/patch_android_singbox_profiles.py"
MULTI_ENGINE_ANDROID = ROOT / "scripts/configure_android_multi_engine.py"


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

    # Finalize the generated Android runtime in deterministic order. Xray keeps
    # its independent HEV packet bridge; sing-box owns a separate libbox TUN;
    # MainActivity is written last so earlier generators cannot overwrite the
    # multi-engine dispatcher.
    runpy.run_path(str(VPN_REGRESSION_FIX), run_name="__main__")
    runpy.run_path(str(HEV_TUN_SETUP), run_name="__main__")
    runpy.run_path(str(HEV_JNI_KEEP), run_name="__main__")
    runpy.run_path(str(MULTI_ENGINE_FLUTTER), run_name="__main__")
    runpy.run_path(str(BUILD_SINGBOX), run_name="__main__")
    runpy.run_path(str(CONFIGURE_SINGBOX), run_name="__main__")
    runpy.run_path(str(PATCH_SINGBOX_PROFILES), run_name="__main__")
    runpy.run_path(str(MULTI_ENGINE_ANDROID), run_name="__main__")


if __name__ == "__main__":
    main()
