#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${WESI_AERO_ANDROID_ABIS:=arm64-v8a}"
: "${WESI_AERO_SINGBOX_TARGET:=android/arm64}"
export WESI_AERO_ANDROID_ABIS WESI_AERO_SINGBOX_TARGET

# Common Android metadata / platform integration. The initial WireGuard setup
# provides Java/desugaring configuration; the final dispatcher is converted to
# one AmneziaWG-compatible backend for both WG profile families below.
python3 scripts/configure_payment_return.py
python3 scripts/configure_android_wireguard.py

# Xray engine: Xray core -> local SOCKS -> pinned hev-socks5-tunnel -> Android TUN.
python3 scripts/download_xray_aar.py
python3 scripts/configure_android_xray.py
python3 scripts/harden_android_xray_datapath.py
python3 scripts/configure_android_hev_tun.py
python3 scripts/fix_android_hev_jni_keep.py

# sing-box engine: libbox owns the Android TUN through PlatformInterface.
python3 scripts/build_android_singbox.py
python3 scripts/configure_android_singbox.py
python3 scripts/fix_android_singbox_iterators.py
python3 scripts/patch_android_singbox_profiles.py

# Runtime dispatcher: sing-box / Xray / native WireGuard-family backend.
python3 scripts/normalize_protocol_engine_matrix.py
python3 scripts/configure_android_multi_engine.py
python3 scripts/enable_android_amneziawg_backend.py
python3 scripts/apply_multi_engine_profiles.py

# UI/control-plane optimizations are intentionally independent of visual quality.
python3 scripts/optimize_flutter_control_plane.py
python3 scripts/fix_flutter_perf_compat.py

# Fail the build if an engine silently disappeared.
test -s android/app/libs/libv2ray.aar
test -s android/app/libs/libbox.aar
test -f android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt
test -f android/app/src/main/kotlin/com/wesi/wesi_aero/AeroSingBoxVpnService.kt
test -f android/app/src/main/kotlin/com/wesi/wesi_aero/TProxyService.kt

grep -q 'android:name=".AeroXrayVpnService"' android/app/src/main/AndroidManifest.xml
grep -q 'android:name=".AeroSingBoxVpnService"' android/app/src/main/AndroidManifest.xml
grep -q 'AeroSingBoxVpnService.start(' android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt
grep -q 'AeroXrayVpnService.start(' android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt
grep -q 'wireGuardBackend.setState' android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt
grep -q 'org.amnezia.awg.backend.GoBackend' android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt
grep -q '"wireguard", "amneziawg" -> setOf("native")' android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt
grep -q 'com.zaneschepke:amneziawg-android:2.3.7' android/app/build.gradle.kts
! grep -q 'com.wireguard.android:tunnel:' android/app/build.gradle.kts
grep -q 'controller.startLoop(runtimeConfig, 0)' android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt
grep -q 'override fun len(): Int = values.size' android/app/src/main/kotlin/com/wesi/wesi_aero/AeroSingBoxVpnService.kt
grep -q 'engineHint' lib/src/models/gateway_models.dart
grep -q "profile\['singBoxConfig'\]" lib/src/services/gateway_engine.dart

for abi in $WESI_AERO_ANDROID_ABIS; do
  test -s "android/app/src/main/jniLibs/$abi/libhev-socks5-tunnel.so"
done

echo "Wesi Aero Android multi-engine runtime verified: sing-box + Xray/hev + WireGuard/AmneziaWG"
