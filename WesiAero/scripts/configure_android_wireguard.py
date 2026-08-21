#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

WIREGUARD_VERSION = "1.0.20260102"
DESUGAR_VERSION = "2.0.3"

ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MAIN_ACTIVITY = (
    ROOT
    / "android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt"
)


def patch_gradle() -> None:
    text = GRADLE.read_text(encoding="utf-8")

    compile_options = re.compile(
        r"compileOptions\s*\{.*?\n\s*\}", re.DOTALL
    )
    replacement = """compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }"""
    if compile_options.search(text):
        text = compile_options.sub(replacement, text, count=1)
    else:
        marker = "android {"
        if marker not in text:
            raise SystemExit(f"Android block not found in {GRADLE}")
        text = text.replace(marker, marker + "\n    " + replacement, 1)

    text = re.sub(
        r"jvmTarget\s*=\s*JavaVersion\.VERSION_\d+\.toString\(\)",
        "jvmTarget = JavaVersion.VERSION_17.toString()",
        text,
    )

    dependency_lines = [
        f'    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VERSION}")',
        f'    implementation("com.wireguard.android:tunnel:{WIREGUARD_VERSION}")',
    ]
    if "com.wireguard.android:tunnel:" not in text:
        text = text.rstrip() + "\n\ndependencies {\n" + "\n".join(dependency_lines) + "\n}\n"

    GRADLE.write_text(text, encoding="utf-8")


def write_activity() -> None:
    MAIN_ACTIVITY.parent.mkdir(parents=True, exist_ok=True)
    MAIN_ACTIVITY.write_text(
        r'''package com.wesi.wesi_aero

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "com.wesi.aero/gateway"
        private const val EVENT_CHANNEL = "com.wesi.aero/gateway-events"
        private const val VPN_PERMISSION_REQUEST = 9107
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var backend: GoBackend
    private val tunnel = AeroTunnel()

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var rawConfig: String? = null
    @Volatile private var activeConfig: Config? = null
    @Volatile private var protocol: String = "amneziawg"
    @Volatile private var status: String = "disconnected"
    @Volatile private var connectedAtMs: Long? = null
    @Volatile private var lastRx: Long = 0
    @Volatile private var lastTx: Long = 0
    @Volatile private var lastStatsAt: Long = 0
    @Volatile private var pendingConnect: PendingConnect? = null

    private val statsTick = object : Runnable {
        override fun run() {
            if (status != "connected") return
            executor.execute {
                try {
                    val stats = backend.getStatistics(tunnel)
                    val now = SystemClock.elapsedRealtime()
                    val rx = stats.totalRx()
                    val tx = stats.totalTx()
                    val elapsed = (now - lastStatsAt).coerceAtLeast(1)
                    val downBps = if (lastStatsAt == 0L) 0 else ((rx - lastRx).coerceAtLeast(0) * 1000L / elapsed)
                    val upBps = if (lastStatsAt == 0L) 0 else ((tx - lastTx).coerceAtLeast(0) * 1000L / elapsed)
                    lastRx = rx
                    lastTx = tx
                    lastStatsAt = now
                    emitSnapshot(
                        downloadBps = downBps,
                        uploadBps = upBps,
                        downloadedBytes = rx,
                        uploadedBytes = tx,
                    )
                } catch (_: Throwable) {
                    // A transient statistics failure must never tear down a healthy tunnel.
                } finally {
                    if (status == "connected") {
                        mainHandler.postDelayed(this, 1000)
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        backend = GoBackend(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadNodes" -> result.success(emptyList<Map<String, Any?>>())
                    "importConfig" -> importConfig(call, result)
                    "connect" -> connect(call, result)
                    "disconnect" -> disconnect(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun importConfig(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("config")?.trim().orEmpty()
        val requestedProtocol = call.argument<String>("protocol") ?: "amneziawg"
        if (value.isEmpty()) {
            result.error("INVALID_CONFIG", "VPN configuration is empty", null)
            return
        }
        if (requestedProtocol != "amneziawg") {
            result.error(
                "PROTOCOL_NOT_READY",
                "The real prototype currently supports WireGuard/AmneziaWG profiles on Android",
                null,
            )
            return
        }

        executor.execute {
            try {
                val parsed = parseConfig(value)
                rawConfig = value
                activeConfig = parsed
                protocol = "amneziawg"
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("INVALID_CONFIG", error.message ?: "Invalid WireGuard configuration", null)
                }
            }
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val original = rawConfig
        if (original.isNullOrBlank()) {
            result.error(
                "PROFILE_REQUIRED",
                "Import a WireGuard profile before connecting",
                null,
            )
            return
        }

        val requestedProtocol = call.argument<String>("protocol") ?: protocol
        if (requestedProtocol != "auto" && requestedProtocol != "amneziawg") {
            result.error(
                "PROTOCOL_NOT_READY",
                "The Android prototype currently uses WireGuard/AmneziaWG",
                null,
            )
            return
        }

        val splitMode = call.argument<String>("splitMode") ?: "allTraffic"
        val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
        val appPackages = rules
            .filter { it["kind"] == "application" }
            .mapNotNull { it["value"] as? String }
            .filter { it.isNotBlank() }
            .distinct()

        val routedConfig = try {
            withApplicationRouting(original, splitMode, appPackages)
        } catch (error: Throwable) {
            result.error("INVALID_SPLIT_ROUTE", error.message, null)
            return
        }

        val parsed = try {
            parseConfig(routedConfig)
        } catch (error: Throwable) {
            result.error("INVALID_CONFIG", error.message, null)
            return
        }

        emitStatus("connecting")
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            pendingConnect = PendingConnect(parsed, result)
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }
        bringUp(parsed, result)
    }

    @Deprecated("Deprecated in Android; retained for VpnService permission compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return
        val pending = pendingConnect ?: return
        pendingConnect = null
        if (resultCode != Activity.RESULT_OK) {
            emitError("VPN_PERMISSION_DENIED", "VPN permission was not granted")
            pending.result.error("VPN_PERMISSION_DENIED", "VPN permission was not granted", null)
            return
        }
        bringUp(pending.config, pending.result)
    }

    private fun bringUp(config: Config, result: MethodChannel.Result) {
        executor.execute {
            try {
                backend.setState(tunnel, Tunnel.State.UP, config)
                activeConfig = config
                connectedAtMs = System.currentTimeMillis()
                lastRx = 0
                lastTx = 0
                lastStatsAt = 0
                status = "connected"
                emitSnapshot()
                mainHandler.removeCallbacks(statsTick)
                mainHandler.post(statsTick)
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                emitError("TUNNEL_START_FAILED", error.message ?: "WireGuard tunnel failed to start")
                mainHandler.post {
                    result.error("TUNNEL_START_FAILED", error.message ?: "WireGuard tunnel failed to start", null)
                }
            }
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        emitStatus("disconnecting")
        mainHandler.removeCallbacks(statsTick)
        executor.execute {
            try {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
                status = "disconnected"
                connectedAtMs = null
                lastRx = 0
                lastTx = 0
                lastStatsAt = 0
                emitSnapshot()
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                emitError("TUNNEL_STOP_FAILED", error.message ?: "WireGuard tunnel failed to stop")
                mainHandler.post {
                    result.error("TUNNEL_STOP_FAILED", error.message ?: "WireGuard tunnel failed to stop", null)
                }
            }
        }
    }

    private fun parseConfig(value: String): Config = Config.parse(
        ByteArrayInputStream(value.toByteArray(StandardCharsets.UTF_8))
    )

    private fun withApplicationRouting(
        source: String,
        splitMode: String,
        applications: List<String>,
    ): String {
        if (splitMode == "allTraffic") return source
        if (applications.isEmpty()) {
            throw IllegalArgumentException("Select at least one application for split routing")
        }

        val routingKey = when (splitMode) {
            "allowlist" -> "IncludedApplications"
            "denylist" -> "ExcludedApplications"
            else -> throw IllegalArgumentException("Unknown split-routing mode")
        }
        val cleaned = source.lineSequence()
            .filterNot {
                val line = it.trimStart()
                line.startsWith("IncludedApplications", ignoreCase = true) ||
                    line.startsWith("ExcludedApplications", ignoreCase = true)
            }
            .toMutableList()
        val peerIndex = cleaned.indexOfFirst { it.trim().equals("[Peer]", ignoreCase = true) }
        if (peerIndex < 0) throw IllegalArgumentException("WireGuard profile has no [Peer] section")
        cleaned.add(peerIndex, "$routingKey = ${applications.joinToString(", ")}")
        return cleaned.joinToString("\n")
    }

    private fun emitStatus(next: String) {
        status = next
        emitSnapshot()
    }

    private fun emitError(code: String, message: String) {
        status = "error"
        emitSnapshot(error = "$code: $message")
    }

    private fun emitSnapshot(
        downloadBps: Long = 0,
        uploadBps: Long = 0,
        downloadedBytes: Long = lastRx,
        uploadedBytes: Long = lastTx,
        error: String? = null,
    ) {
        val payload = hashMapOf<String, Any?>(
            "status" to status,
            "protocol" to protocol,
            "downloadBps" to downloadBps.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            "uploadBps" to uploadBps.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            "downloadedBytes" to downloadedBytes,
            "uploadedBytes" to uploadedBytes,
            "connectedAt" to connectedAtMs?.let { Instant.ofEpochMilli(it).toString() },
            "pingMs" to null,
            "node" to null,
            "error" to error,
        )
        mainHandler.post { eventSink?.success(payload) }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(statsTick)
        executor.shutdown()
        super.onDestroy()
    }

    private inner class AeroTunnel : Tunnel {
        override fun getName(): String = "WesiAero"

        override fun onStateChange(newState: Tunnel.State) {
            status = when (newState) {
                Tunnel.State.UP -> "connected"
                Tunnel.State.DOWN -> "disconnected"
                Tunnel.State.TOGGLE -> status
            }
            emitSnapshot()
        }
    }

    private data class PendingConnect(
        val config: Config,
        val result: MethodChannel.Result,
    )
}
''',
        encoding="utf-8",
    )


def main() -> None:
    if not GRADLE.is_file():
        raise SystemExit(f"Android Gradle file not found: {GRADLE}")
    patch_gradle()
    write_activity()
    print(f"Configured native WireGuard Android backend ({WIREGUARD_VERSION})")


if __name__ == "__main__":
    main()
