#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt"
XRAY = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt"
SING = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroSingBoxVpnService.kt"

MAIN_SOURCE = r'''package com.wesi.wesi_aero

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
    private lateinit var wireGuardBackend: GoBackend
    private val wireGuardTunnel = AeroTunnel()

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var rawConfig: String? = null
    @Volatile private var profileProtocol: String = "vless-reality"
    @Volatile private var profileEngine: String = "auto"
    @Volatile private var protocol: String = "vless-reality"
    @Volatile private var engine: String = "auto"
    @Volatile private var status: String = "disconnected"
    @Volatile private var connectedAtMs: Long? = null
    @Volatile private var lastRx: Long = 0
    @Volatile private var lastTx: Long = 0
    @Volatile private var lastStatsAt: Long = 0
    @Volatile private var activeBackend: String? = null
    @Volatile private var pendingConnect: PendingConnect? = null

    private val wireGuardStatsTick = object : Runnable {
        override fun run() {
            if (status != "connected" || activeBackend != "native") return
            executor.execute {
                try {
                    val stats = wireGuardBackend.getStatistics(wireGuardTunnel)
                    val now = SystemClock.elapsedRealtime()
                    val rx = stats.totalRx()
                    val tx = stats.totalTx()
                    val elapsed = (now - lastStatsAt).coerceAtLeast(1)
                    val down = if (lastStatsAt == 0L) 0 else ((rx - lastRx).coerceAtLeast(0) * 1000L / elapsed)
                    val up = if (lastStatsAt == 0L) 0 else ((tx - lastTx).coerceAtLeast(0) * 1000L / elapsed)
                    lastRx = rx
                    lastTx = tx
                    lastStatsAt = now
                    emitSnapshot(down, up, rx, tx)
                } catch (_: Throwable) {
                } finally {
                    if (status == "connected" && activeBackend == "native") {
                        mainHandler.postDelayed(this, 1000)
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wireGuardBackend = GoBackend(applicationContext)
        AeroXrayState.listener = { snapshot ->
            if (activeBackend != "xray" && snapshot.status == "disconnected") return@listener
            protocol = canonicalProtocol(snapshot.protocol)
            engine = "xray"
            status = snapshot.status
            connectedAtMs = snapshot.connectedAtMs
            if (snapshot.status == "disconnected" && activeBackend == "xray") activeBackend = null
            emitSnapshot(
                snapshot.downloadBps,
                snapshot.uploadBps,
                snapshot.downloadedBytes,
                snapshot.uploadedBytes,
                snapshot.error,
            )
        }
        AeroSingBoxState.listener = { snapshot ->
            if (activeBackend != "sing-box" && snapshot.status == "disconnected") return@listener
            protocol = canonicalProtocol(snapshot.protocol)
            engine = "sing-box"
            status = snapshot.status
            connectedAtMs = snapshot.connectedAtMs
            if (snapshot.status == "disconnected" && activeBackend == "sing-box") activeBackend = null
            emitSnapshot(error = snapshot.error)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
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
        val requestedProtocol = canonicalProtocol(call.argument<String>("protocol") ?: "vless-reality")
        val requestedEngine = call.argument<String>("engine") ?: "auto"
        if (value.isEmpty()) {
            result.error("INVALID_CONFIG", "VPN configuration is empty", null)
            return
        }
        val resolvedEngine = if (requestedEngine == "auto") defaultEngine(requestedProtocol) else requestedEngine
        try {
            validateCombination(requestedProtocol, resolvedEngine)
            when (resolvedEngine) {
                "sing-box" -> require(value.startsWith("{")) { "sing-box profile must be JSON" }
                "xray" -> XrayConfigFactory.build(value, xrayProtocol(requestedProtocol))
                "native" -> {
                    if (requestedProtocol != "wireguard") {
                        throw IllegalArgumentException("Native backend is not ready for $requestedProtocol")
                    }
                    parseWireGuardConfig(value)
                }
                else -> throw IllegalArgumentException("Unknown VPN engine: $resolvedEngine")
            }
            rawConfig = value
            profileProtocol = requestedProtocol
            profileEngine = resolvedEngine
            protocol = requestedProtocol
            engine = resolvedEngine
            result.success(null)
        } catch (error: Throwable) {
            result.error("INVALID_CONFIG", error.message ?: "Invalid VPN configuration", null)
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val config = rawConfig
        if (config.isNullOrBlank()) {
            result.error("PROFILE_REQUIRED", "Import a server profile before connecting", null)
            return
        }
        var requestedProtocol = canonicalProtocol(call.argument<String>("protocol") ?: profileProtocol)
        if (requestedProtocol == "auto") requestedProtocol = profileProtocol
        var requestedEngine = call.argument<String>("engine") ?: profileEngine
        if (requestedEngine == "auto") requestedEngine = defaultEngine(requestedProtocol)
        if (requestedProtocol != profileProtocol || requestedEngine != profileEngine) {
            result.error(
                "PROFILE_ENGINE_MISMATCH",
                "The imported profile does not match the selected protocol/engine",
                null,
            )
            return
        }
        try {
            validateCombination(requestedProtocol, requestedEngine)
        } catch (error: Throwable) {
            result.error("ENGINE_UNAVAILABLE", error.message, null)
            return
        }

        val splitMode = call.argument<String>("splitMode") ?: "allTraffic"
        val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
        val packages = rules
            .filter { it["kind"] == "application" }
            .mapNotNull { it["value"] as? String }
            .filter { it.isNotBlank() }
            .distinct()
        val pending = PendingConnect(
            requestedProtocol,
            requestedEngine,
            config,
            splitMode,
            packages,
            result,
        )
        protocol = requestedProtocol
        engine = requestedEngine
        status = "connecting"
        emitSnapshot()
        val permission = VpnService.prepare(this)
        if (permission != null) {
            pendingConnect = pending
            startActivityForResult(permission, VPN_PERMISSION_REQUEST)
        } else {
            bringUp(pending)
        }
    }

    @Deprecated("Retained for VpnService permission flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return
        val pending = pendingConnect ?: return
        pendingConnect = null
        if (resultCode != Activity.RESULT_OK) {
            status = "error"
            emitSnapshot(error = "VPN_PERMISSION_DENIED: VPN permission was not granted")
            pending.result.error("VPN_PERMISSION_DENIED", "VPN permission was not granted", null)
            return
        }
        bringUp(pending)
    }

    private fun bringUp(pending: PendingConnect) {
        executor.execute {
            try {
                stopEveryBackend()
                protocol = pending.protocol
                engine = pending.engine
                when (pending.engine) {
                    "sing-box" -> {
                        activeBackend = "sing-box"
                        AeroSingBoxVpnService.start(
                            this,
                            pending.protocol,
                            pending.rawConfig,
                            pending.splitMode,
                            pending.appPackages,
                        )
                    }
                    "xray" -> {
                        activeBackend = "xray"
                        AeroXrayVpnService.start(
                            this,
                            xrayProtocol(pending.protocol),
                            pending.rawConfig,
                            pending.splitMode,
                            pending.appPackages,
                        )
                    }
                    "native" -> bringUpWireGuard(pending)
                }
                mainHandler.post { pending.result.success(null) }
            } catch (error: Throwable) {
                activeBackend = null
                status = "error"
                emitSnapshot(error = "TUNNEL_START_FAILED: ${error.message ?: error.javaClass.simpleName}")
                mainHandler.post {
                    pending.result.error("TUNNEL_START_FAILED", error.message ?: "VPN engine failed", null)
                }
            }
        }
    }

    private fun bringUpWireGuard(pending: PendingConnect) {
        if (pending.protocol != "wireguard") {
            throw IllegalStateException("Real AmneziaWG backend is not installed yet")
        }
        val routed = withApplicationRouting(pending.rawConfig, pending.splitMode, pending.appPackages)
        val parsed = parseWireGuardConfig(routed)
        wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.UP, parsed)
        activeBackend = "native"
        engine = "native"
        status = "connected"
        connectedAtMs = System.currentTimeMillis()
        lastRx = 0
        lastTx = 0
        lastStatsAt = 0
        emitSnapshot()
        mainHandler.removeCallbacks(wireGuardStatsTick)
        mainHandler.post(wireGuardStatsTick)
    }

    private fun stopEveryBackend() {
        mainHandler.removeCallbacks(wireGuardStatsTick)
        try { wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.DOWN, null) } catch (_: Throwable) {}
        AeroXrayVpnService.stop(this)
        AeroSingBoxVpnService.stop(this)

        var vpnServicesReleased = false
        for (attempt in 0 until 60) {
            val xrayDown = AeroXrayState.current().status == "disconnected"
            val singDown = AeroSingBoxState.current().status == "disconnected"
            if (xrayDown && singDown) {
                vpnServicesReleased = true
                break
            }
            Thread.sleep(50L)
        }
        if (!vpnServicesReleased) {
            throw IllegalStateException("Previous VPN backend did not release Android TUN")
        }

        connectedAtMs = null
        lastRx = 0
        lastTx = 0
        lastStatsAt = 0
    }

    private fun disconnect(result: MethodChannel.Result) {
        status = "disconnecting"
        emitSnapshot()
        executor.execute {
            try {
                stopEveryBackend()
                activeBackend = null
                status = "disconnected"
                engine = "auto"
                emitSnapshot()
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                status = "error"
                emitSnapshot(error = "TUNNEL_STOP_FAILED: ${error.message ?: error.javaClass.simpleName}")
                mainHandler.post { result.error("TUNNEL_STOP_FAILED", error.message, null) }
            }
        }
    }

    private fun validateCombination(protocol: String, engine: String) {
        val supported = when (protocol) {
            "vless-reality", "vmess" -> setOf("sing-box", "xray")
            "trojan", "shadowsocks", "hysteria2", "tuic" -> setOf("sing-box")
            "wireguard" -> setOf("native")
            "amneziawg" -> emptySet()
            else -> emptySet()
        }
        require(engine in supported) { "$engine does not support $protocol in this build" }
    }

    private fun defaultEngine(protocol: String): String = when (protocol) {
        "vless-reality", "vmess", "trojan", "shadowsocks", "hysteria2", "tuic" -> "sing-box"
        "wireguard" -> "native"
        else -> "native"
    }

    private fun canonicalProtocol(value: String): String = when (value) {
        "vmess-xray" -> "vmess"
        else -> value
    }

    private fun xrayProtocol(value: String): String = when (value) {
        "vmess" -> "vmess-xray"
        else -> value
    }

    private fun parseWireGuardConfig(value: String): Config = Config.parse(
        ByteArrayInputStream(value.toByteArray(StandardCharsets.UTF_8))
    )

    private fun withApplicationRouting(source: String, splitMode: String, applications: List<String>): String {
        if (splitMode == "allTraffic") return source
        if (applications.isEmpty()) throw IllegalArgumentException("Select at least one application")
        val key = when (splitMode) {
            "allowlist" -> "IncludedApplications"
            "denylist" -> "ExcludedApplications"
            else -> throw IllegalArgumentException("Unknown split-routing mode")
        }
        val lines = source.lineSequence().filterNot {
            val line = it.trimStart()
            line.startsWith("IncludedApplications", true) || line.startsWith("ExcludedApplications", true)
        }.toMutableList()
        val peer = lines.indexOfFirst { it.trim().equals("[Peer]", true) }
        if (peer < 0) throw IllegalArgumentException("WireGuard profile has no [Peer]")
        lines.add(peer, "$key = ${applications.joinToString(", ")}")
        return lines.joinToString("\n")
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
            "protocol" to canonicalProtocol(protocol),
            "engine" to engine,
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
        mainHandler.removeCallbacks(wireGuardStatsTick)
        AeroXrayState.listener = null
        AeroSingBoxState.listener = null
        executor.shutdownNow()
        super.onDestroy()
    }

    private inner class AeroTunnel : Tunnel {
        override fun getName(): String = "WesiAero"
        override fun onStateChange(newState: Tunnel.State) {
            if (activeBackend != "native") return
            status = when (newState) {
                Tunnel.State.UP -> "connected"
                Tunnel.State.DOWN -> "disconnected"
                Tunnel.State.TOGGLE -> status
            }
            if (newState == Tunnel.State.DOWN) connectedAtMs = null
            emitSnapshot()
        }
    }

    private data class PendingConnect(
        val protocol: String,
        val engine: String,
        val rawConfig: String,
        val splitMode: String,
        val appPackages: List<String>,
        val result: MethodChannel.Result,
    )
}
'''


def main() -> None:
    if not XRAY.is_file() or not SING.is_file():
        raise SystemExit("Configure Xray and sing-box services before multi-engine dispatcher")
    MAIN.write_text(MAIN_SOURCE, encoding="utf-8")
    text = MAIN.read_text(encoding="utf-8")
    required = [
        '"engine" to engine',
        'AeroSingBoxVpnService.start(',
        'AeroXrayVpnService.start(',
        'wireGuardBackend.setState',
        '"vless-reality", "vmess" -> setOf("sing-box", "xray")',
        '"amneziawg" -> emptySet()',
        'Previous VPN backend did not release Android TUN',
    ]
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit(f"multi-engine dispatcher verification failed: {missing}")
    if 'return@repeat' in text:
        raise SystemExit("multi-engine dispatcher contains non-breaking TUN wait")
    print("Configured Android multi-engine dispatcher: sing-box + Xray + native WireGuard + fail-closed TUN handoff")


if __name__ == "__main__":
    main()
