#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt"
TPROXY = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/TProxyService.kt"
JNI_LIBS = ROOT / "android/app/src/main/jniLibs"
HEV_REPO = "https://github.com/heiher/hev-socks5-tunnel.git"
# Exact submodule revision used by v2rayNG current Android VPN implementation.
HEV_COMMIT = "64cc609f945253b0e9ebc56317d544268f3c68c1"
ABIS = os.environ.get(
    "WESI_AERO_ANDROID_ABIS", "armeabi-v7a arm64-v8a x86_64"
).split()


def run(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def find_ndk() -> Path:
    for key in ("NDK_HOME", "ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        raw = os.environ.get(key)
        if raw and (Path(raw) / "ndk-build").is_file():
            return Path(raw)
    sdk_raw = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk_raw:
        ndk_root = Path(sdk_raw) / "ndk"
        if ndk_root.is_dir():
            candidates = sorted(
                (p for p in ndk_root.iterdir() if (p / "ndk-build").is_file()),
                reverse=True,
            )
            if candidates:
                return candidates[0]
    raise SystemExit("Android NDK with ndk-build was not found")


def build_native() -> None:
    ndk = find_ndk()
    with tempfile.TemporaryDirectory(prefix="wesi-hev-") as tmp_raw:
        tmp = Path(tmp_raw)
        source = tmp / "hev"
        project = tmp / "ndk"
        libs_out = tmp / "libs"
        obj_out = tmp / "obj"
        run("git", "clone", "--recursive", HEV_REPO, str(source))
        run("git", "checkout", HEV_COMMIT, cwd=source)
        run("git", "submodule", "update", "--init", "--recursive", cwd=source)
        (project / "jni").mkdir(parents=True)
        os.symlink(source, project / "jni" / "hev-socks5-tunnel", target_is_directory=True)
        (project / "jni" / "Android.mk").write_text(
            "include $(call all-subdir-makefiles)\n", encoding="utf-8"
        )
        run(
            str(ndk / "ndk-build"),
            f"NDK_PROJECT_PATH={project}",
            f"APP_BUILD_SCRIPT={project / 'jni' / 'Android.mk'}",
            f"APP_ABI={' '.join(ABIS)}",
            "APP_PLATFORM=android-23",
            f"NDK_LIBS_OUT={libs_out}",
            f"NDK_OUT={obj_out}",
            "APP_CFLAGS=-O3 -DPKGNAME=com/wesi/wesi_aero",
            "APP_LDFLAGS=-Wl,--build-id=none -Wl,--hash-style=gnu -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384",
        )
        for abi in ABIS:
            source_so = libs_out / abi / "libhev-socks5-tunnel.so"
            if not source_so.is_file():
                raise SystemExit(f"hev-socks5-tunnel build is missing {source_so}")
            target_dir = JNI_LIBS / abi
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_so, target_dir / source_so.name)


def write_kotlin_bridge() -> None:
    TPROXY.parent.mkdir(parents=True, exist_ok=True)
    TPROXY.write_text(
        r'''package com.wesi.wesi_aero

import android.content.Context
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * Battle-tested Android TUN -> SOCKS bridge used by v2rayNG as its hev-tun mode.
 * Xray owns only the local SOCKS proxy; this class owns packet translation.
 */
internal class TProxyService(
    private val context: Context,
    private val vpnInterface: ParcelFileDescriptor,
) {
    companion object {
        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyStartService(configPath: String, fd: Int): Boolean

        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyStopService(): Boolean

        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyIsRunning(): Boolean

        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyGetStats(): LongArray?

        init {
            System.loadLibrary("hev-socks5-tunnel")
        }
    }

    fun startTun2Socks(): Boolean {
        val configFile = File(context.filesDir, "wesi-hev-socks5-tunnel.yaml")
        configFile.writeText(
            """tunnel:
  mtu: 1500
  ipv4: 172.31.255.2
socks5:
  port: 10808
  address: 127.0.0.1
  udp: 'udp'
misc:
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
  log-level: warn
"""
        )
        if (!TProxyStartService(configFile.absolutePath, vpnInterface.fd)) return false
        repeat(40) {
            if (TProxyIsRunning()) return true
            Thread.sleep(25L)
        }
        TProxyStopService()
        return false
    }

    fun stopTun2Socks() {
        try {
            TProxyStopService()
        } catch (_: Throwable) {
        }
    }

    /** Returns txPackets, txBytes, rxPackets, rxBytes. */
    fun stats(): LongArray = try {
        TProxyGetStats() ?: longArrayOf(0, 0, 0, 0)
    } catch (_: Throwable) {
        longArrayOf(0, 0, 0, 0)
    }
}
''',
        encoding="utf-8",
    )


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_xray_service() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "    private var core: CoreController? = null\n    private var tun: ParcelFileDescriptor? = null\n",
        "    private var core: CoreController? = null\n"
        "    private var tun: ParcelFileDescriptor? = null\n"
        "    private var tun2Socks: TProxyService? = null\n",
        "tun2socks field",
    )

    text = replace_once(
        text,
        "            controller.startLoop(runtimeConfig, established.fd)\n"
        "            if (!controller.isRunning) {\n"
        "                throw IllegalStateException(\"Xray core did not enter running state\")\n"
        "            }\n",
        "            // Xray is proxy-only here. HevSocks5Tunnel consumes the Android\n"
        "            // TUN fd and forwards TCP/UDP to Xray's local SOCKS inbound.\n"
        "            controller.startLoop(runtimeConfig, 0)\n"
        "            if (!controller.isRunning) {\n"
        "                throw IllegalStateException(\"Xray core did not enter running state\")\n"
        "            }\n"
        "            val packetBridge = TProxyService(this, established)\n"
        "            if (!packetBridge.startTun2Socks()) {\n"
        "                throw IllegalStateException(\"Android TUN packet bridge did not start\")\n"
        "            }\n"
        "            tun2Socks = packetBridge\n",
        "proxy-only Xray + hev startup",
    )

    # The hardening step creates both SOCKS and built-in TUN inbounds. Keep only
    # SOCKS: the Android packet fd is now owned by hev-socks5-tunnel.
    text = replace_once(
        text,
        '.put("inbounds", JSONArray().put(socksInbound).put(tunInbound))',
        '.put("inbounds", JSONArray().put(socksInbound))',
        "proxy-only inbound list",
    )

    # A routing rule that references the removed TUN inbound is unnecessary.
    # SOCKS traffic naturally uses the first (proxy) outbound.
    text = text.replace(
        '.put("rules",\n                        JSONArray().put(\n                            JSONObject()\n                                .put("type", "field")\n                                .put("inboundTag", JSONArray().put("tun"))\n                                .put("outboundTag", "proxy"),\n                        ),\n                    )',
        '.put("rules", JSONArray())',
        1,
    )

    text = replace_once(
        text,
        "    private fun stopTunnel(stopService: Boolean) {\n"
        "        mainHandler.removeCallbacks(statsTick)\n",
        "    private fun stopTunnel(stopService: Boolean) {\n"
        "        mainHandler.removeCallbacks(statsTick)\n"
        "        tun2Socks?.stopTun2Socks()\n"
        "        tun2Socks = null\n",
        "tun2socks stop",
    )

    text = replace_once(
        text,
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n",
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n"
        "        tun2Socks?.stopTun2Socks()\n"
        "        tun2Socks = null\n",
        "tun2socks destroy",
    )

    # Verify the generated service no longer hands the Android fd directly to
    # Xray. That built-in path is the one that connected without moving traffic
    # on the target phone.
    if "controller.startLoop(runtimeConfig, established.fd)" in text:
        raise SystemExit("Built-in Xray TUN path unexpectedly remains enabled")
    if "controller.startLoop(runtimeConfig, 0)" not in text:
        raise SystemExit("Proxy-only Xray startup is missing")
    if '.put("inbounds", JSONArray().put(socksInbound))' not in text:
        raise SystemExit("SOCKS-only Xray runtime is missing")
    SERVICE.write_text(text, encoding="utf-8")


def main() -> None:
    if not SERVICE.is_file():
        raise SystemExit("Generate and harden Android Xray service before configuring hev tun")
    build_native()
    write_kotlin_bridge()
    patch_xray_service()
    for abi in ABIS:
        so = JNI_LIBS / abi / "libhev-socks5-tunnel.so"
        if not so.is_file() or so.stat().st_size < 100_000:
            raise SystemExit(f"Invalid native tun2socks library: {so}")
    print(
        "Configured Android packet path: VpnService TUN -> hev-socks5-tunnel -> "
        "Xray SOCKS -> VLESS/VMess"
    )


if __name__ == "__main__":
    main()
