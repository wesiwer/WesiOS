#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TPROXY = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/TProxyService.kt"
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_bridge_keep() -> None:
    text = TPROXY.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import android.os.ParcelFileDescriptor\nimport java.io.File\n",
        "import android.os.ParcelFileDescriptor\nimport androidx.annotation.Keep\nimport java.io.File\n",
        "androidx Keep import",
    )
    text = replace_once(
        text,
        "internal class TProxyService(\n",
        "@Keep\ninternal class TProxyService(\n",
        "TProxyService keep annotation",
    )
    # RegisterNatives in hev-jni.c resolves these exact method names at
    # JNI_OnLoad. Keep every native declaration even if a future optimization
    # temporarily stops calling one of them.
    for method in (
        "TProxyStartService",
        "TProxyStopService",
        "TProxyIsRunning",
        "TProxyGetStats",
    ):
        anchor = f'        @JvmStatic\n        @Suppress("FunctionName")\n        private external fun {method}'
        replacement = f'        @Keep\n        @JvmStatic\n        @Suppress("FunctionName")\n        private external fun {method}'
        text = replace_once(text, anchor, replacement, f"keep {method}")
    TPROXY.write_text(text, encoding="utf-8")


def patch_bridge_telemetry() -> None:
    text = SERVICE.read_text(encoding="utf-8")
    old = '''                    val down = controller.queryStats("proxy", "downlink").coerceAtLeast(0)
                    val up = controller.queryStats("proxy", "uplink").coerceAtLeast(0)
                    downloadedBytes += down
                    uploadedBytes += up
'''
    new = '''                    val down = controller.queryStats("proxy", "downlink").coerceAtLeast(0)
                    val up = controller.queryStats("proxy", "uplink").coerceAtLeast(0)
                    // Reading native bridge counters is both useful diagnostics and
                    // intentionally keeps all hev RegisterNatives methods reachable
                    // in release/R8 builds. Array: txPackets, txBytes, rxPackets, rxBytes.
                    val bridge = tun2Socks?.stats()
                    val bridgeTxBytes = bridge?.getOrNull(1)?.coerceAtLeast(0) ?: 0
                    val bridgeRxBytes = bridge?.getOrNull(3)?.coerceAtLeast(0) ?: 0
                    downloadedBytes = maxOf(downloadedBytes + down, bridgeRxBytes)
                    uploadedBytes = maxOf(uploadedBytes + up, bridgeTxBytes)
'''
    text = replace_once(text, old, new, "hev bridge telemetry")
    if "tun2Socks?.stats()" not in text:
        raise SystemExit("Hev bridge stats call is missing from generated service")
    SERVICE.write_text(text, encoding="utf-8")


def main() -> None:
    if not TPROXY.is_file() or not SERVICE.is_file():
        raise SystemExit("Configure hev tun before applying JNI keep protection")
    patch_bridge_keep()
    patch_bridge_telemetry()
    bridge = TPROXY.read_text(encoding="utf-8")
    for method in (
        "TProxyStartService",
        "TProxyStopService",
        "TProxyIsRunning",
        "TProxyGetStats",
    ):
        if method not in bridge:
            raise SystemExit(f"JNI method disappeared before Android build: {method}")
    print("Protected hev JNI RegisterNatives methods from R8 and enabled bridge telemetry")


if __name__ == "__main__":
    main()
