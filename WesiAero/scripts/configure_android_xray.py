#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
KOTLIN_DIR = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero"
MAIN_ACTIVITY = KOTLIN_DIR / "MainActivity.kt"
XRAY_SERVICE = KOTLIN_DIR / "AeroXrayVpnService.kt"
AAR = ROOT / "android/app/libs/libv2ray.aar"


def patch_gradle() -> None:
    text = GRADLE.read_text(encoding="utf-8")
    marker = 'implementation(files("libs/libv2ray.aar"))'
    if marker not in text:
        text = text.rstrip() + f'\n\ndependencies {{\n    {marker}\n}}\n'
    GRADLE.write_text(text, encoding="utf-8")


def patch_manifest() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    ]
    insertion = "\n    ".join(p for p in permissions if p not in text)
    if insertion:
        manifest_open = re.search(r"<manifest[^>]*>", text)
        if not manifest_open:
            raise SystemExit(f"Manifest root not found in {MANIFEST}")
        pos = manifest_open.end()
        text = text[:pos] + "\n    " + insertion + text[pos:]

    service = '''
        <service
            android:name=".AeroXrayVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="false"
            android:foregroundServiceType="systemExempted"
            android:stopWithTask="false">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
'''
    if 'android:name=".AeroXrayVpnService"' not in text:
        text = text.replace("</application>", service + "    </application>", 1)
    MANIFEST.write_text(text, encoding="utf-8")


def write_main_activity() -> None:
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
    private lateinit var wireGuardBackend: GoBackend
    private val wireGuardTunnel = AeroTunnel()

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var rawConfig: String? = null
    @Volatile private var activeWireGuardConfig: Config? = null
    @Volatile private var protocol: String = "vless-reality"
    @Volatile private var status: String = "disconnected"
    @Volatile private var connectedAtMs: Long? = null
    @Volatile private var lastRx: Long = 0
    @Volatile private var lastTx: Long = 0
    @Volatile private var lastStatsAt: Long = 0
    @Volatile private var xrayActive: Boolean = false
    @Volatile private var pendingConnect: PendingConnect? = null

    private val wireGuardStatsTick = object : Runnable {
        override fun run() {
            if (status != "connected" || xrayActive) return
            executor.execute {
                try {
                    val stats = wireGuardBackend.getStatistics(wireGuardTunnel)
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
                    // Statistics are best-effort and must not stop a healthy tunnel.
                } finally {
                    if (status == "connected" && !xrayActive) {
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
            protocol = snapshot.protocol
            status = snapshot.status
            connectedAtMs = snapshot.connectedAtMs
            xrayActive = snapshot.status != "disconnected"
            emitSnapshot(
                downloadBps = snapshot.downloadBps,
                uploadBps = snapshot.uploadBps,
                downloadedBytes = snapshot.downloadedBytes,
                uploadedBytes = snapshot.uploadedBytes,
                error = snapshot.error,
            )
        }
        AeroXrayState.current().also { current ->
            if (current.status != "disconnected") {
                protocol = current.protocol
                status = current.status
                connectedAtMs = current.connectedAtMs
                xrayActive = true
            }
        }
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
        val xray = AeroXrayState.current()
        if (xray.status != "disconnected") {
            emitSnapshot(
                downloadBps = xray.downloadBps,
                uploadBps = xray.uploadBps,
                downloadedBytes = xray.downloadedBytes,
                uploadedBytes = xray.uploadedBytes,
                error = xray.error,
            )
        } else {
            emitSnapshot()
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun importConfig(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("config")?.trim().orEmpty()
        val requestedProtocol = call.argument<String>("protocol") ?: "vless-reality"
        if (value.isEmpty()) {
            result.error("INVALID_CONFIG", "VPN configuration is empty", null)
            return
        }
        if (requestedProtocol !in setOf("vless-reality", "vmess-xray", "amneziawg")) {
            result.error("PROTOCOL_NOT_READY", "Unsupported VPN protocol", null)
            return
        }

        executor.execute {
            try {
                if (requestedProtocol == "amneziawg") {
                    activeWireGuardConfig = parseWireGuardConfig(value)
                } else {
                    XrayConfigFactory.build(value, requestedProtocol)
                    activeWireGuardConfig = null
                }
                rawConfig = value
                protocol = requestedProtocol
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("INVALID_CONFIG", error.message ?: "Invalid VPN configuration", null)
                }
            }
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val original = rawConfig
        if (original.isNullOrBlank()) {
            result.error(
                "PROFILE_REQUIRED",
                "Import a VLESS, VMess or WireGuard profile before connecting",
                null,
            )
            return
        }

        var requestedProtocol = call.argument<String>("protocol") ?: protocol
        if (requestedProtocol == "auto") requestedProtocol = protocol
        if (requestedProtocol != protocol) {
            result.error(
                "PROFILE_PROTOCOL_MISMATCH",
                "The selected protocol does not match the imported profile",
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

        val pending = PendingConnect(
            protocol = requestedProtocol,
            rawConfig = original,
            splitMode = splitMode,
            appPackages = appPackages,
            result = result,
        )
        emitStatus("connecting")
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            pendingConnect = pending
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }
        bringUp(pending)
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
        bringUp(pending)
    }

    private fun bringUp(pending: PendingConnect) {
        if (pending.protocol == "amneziawg") {
            bringUpWireGuard(pending)
        } else {
            bringUpXray(pending)
        }
    }

    private fun bringUpWireGuard(pending: PendingConnect) {
        val routedConfig = try {
            withApplicationRouting(pending.rawConfig, pending.splitMode, pending.appPackages)
        } catch (error: Throwable) {
            pending.result.error("INVALID_SPLIT_ROUTE", error.message, null)
            return
        }
        val parsed = try {
            parseWireGuardConfig(routedConfig)
        } catch (error: Throwable) {
            pending.result.error("INVALID_CONFIG", error.message, null)
            return
        }

        executor.execute {
            try {
                if (xrayActive) AeroXrayVpnService.stop(this)
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.UP, parsed)
                activeWireGuardConfig = parsed
                connectedAtMs = System.currentTimeMillis()
                lastRx = 0
                lastTx = 0
                lastStatsAt = 0
                xrayActive = false
                status = "connected"
                emitSnapshot()
                mainHandler.removeCallbacks(wireGuardStatsTick)
                mainHandler.post(wireGuardStatsTick)
                mainHandler.post { pending.result.success(null) }
            } catch (error: Throwable) {
                emitError("TUNNEL_START_FAILED", error.message ?: "WireGuard tunnel failed to start")
                mainHandler.post {
                    pending.result.error("TUNNEL_START_FAILED", error.message ?: "WireGuard tunnel failed to start", null)
                }
            }
        }
    }

    private fun bringUpXray(pending: PendingConnect) {
        executor.execute {
            try {
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.DOWN, null)
            } catch (_: Throwable) {
                // It is valid for WireGuard to already be down.
            }
            mainHandler.removeCallbacks(wireGuardStatsTick)
            xrayActive = true
            protocol = pending.protocol
            AeroXrayVpnService.start(
                context = this,
                protocol = pending.protocol,
                rawConfig = pending.rawConfig,
                splitMode = pending.splitMode,
                appPackages = pending.appPackages,
            )
            mainHandler.post { pending.result.success(null) }
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        emitStatus("disconnecting")
        mainHandler.removeCallbacks(wireGuardStatsTick)
        if (xrayActive || AeroXrayState.current().status != "disconnected") {
            AeroXrayVpnService.stop(this)
            mainHandler.post { result.success(null) }
            return
        }
        executor.execute {
            try {
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.DOWN, null)
                resetDisconnected()
                mainHandler.post { result.success(null) }
            } catch (error: Throwable) {
                emitError("TUNNEL_STOP_FAILED", error.message ?: "WireGuard tunnel failed to stop")
                mainHandler.post {
                    result.error("TUNNEL_STOP_FAILED", error.message ?: "WireGuard tunnel failed to stop", null)
                }
            }
        }
    }

    private fun parseWireGuardConfig(value: String): Config = Config.parse(
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

    private fun resetDisconnected() {
        status = "disconnected"
        connectedAtMs = null
        lastRx = 0
        lastTx = 0
        lastStatsAt = 0
        xrayActive = false
        emitSnapshot()
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
        mainHandler.removeCallbacks(wireGuardStatsTick)
        if (AeroXrayState.listener != null) AeroXrayState.listener = null
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
            if (newState == Tunnel.State.DOWN) connectedAtMs = null
            emitSnapshot()
        }
    }

    private data class PendingConnect(
        val protocol: String,
        val rawConfig: String,
        val splitMode: String,
        val appPackages: List<String>,
        val result: MethodChannel.Result,
    )
}
''',
        encoding="utf-8",
    )


def write_xray_service() -> None:
    XRAY_SERVICE.write_text(
        r'''package com.wesi.wesi_aero

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Base64
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal data class AeroXraySnapshot(
    val status: String = "disconnected",
    val protocol: String = "vless-reality",
    val connectedAtMs: Long? = null,
    val downloadBps: Long = 0,
    val uploadBps: Long = 0,
    val downloadedBytes: Long = 0,
    val uploadedBytes: Long = 0,
    val error: String? = null,
)

internal object AeroXrayState {
    @Volatile private var snapshot = AeroXraySnapshot()
    @Volatile var listener: ((AeroXraySnapshot) -> Unit)? = null

    fun current(): AeroXraySnapshot = snapshot

    fun publish(next: AeroXraySnapshot) {
        snapshot = next
        listener?.invoke(next)
    }
}

class AeroXrayVpnService : VpnService() {
    companion object {
        private const val ACTION_START = "com.wesi.aero.XRAY_START"
        private const val ACTION_STOP = "com.wesi.aero.XRAY_STOP"
        private const val EXTRA_PROTOCOL = "protocol"
        private const val EXTRA_CONFIG = "config"
        private const val EXTRA_SPLIT_MODE = "splitMode"
        private const val EXTRA_PACKAGES = "packages"
        private const val NOTIFICATION_CHANNEL = "wesi_aero_vpn"
        private const val NOTIFICATION_ID = 22081

        fun start(
            context: Context,
            protocol: String,
            rawConfig: String,
            splitMode: String,
            appPackages: List<String>,
        ) {
            val intent = Intent(context, AeroXrayVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_PROTOCOL, protocol)
                .putExtra(EXTRA_CONFIG, rawConfig)
                .putExtra(EXTRA_SPLIT_MODE, splitMode)
                .putStringArrayListExtra(EXTRA_PACKAGES, ArrayList(appPackages))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AeroXrayVpnService::class.java)
                .setAction(ACTION_STOP)
            context.startService(intent)
        }
    }

    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var core: CoreController? = null
    private var tun: ParcelFileDescriptor? = null
    private var protocol: String = "vless-reality"
    private var connectedAtMs: Long? = null
    private var downloadedBytes: Long = 0
    private var uploadedBytes: Long = 0

    private val statsTick = object : Runnable {
        override fun run() {
            val controller = core ?: return
            worker.execute {
                try {
                    val down = controller.queryStats("proxy", "downlink").coerceAtLeast(0)
                    val up = controller.queryStats("proxy", "uplink").coerceAtLeast(0)
                    downloadedBytes += down
                    uploadedBytes += up
                    AeroXrayState.publish(
                        AeroXraySnapshot(
                            status = "connected",
                            protocol = protocol,
                            connectedAtMs = connectedAtMs,
                            downloadBps = down,
                            uploadBps = up,
                            downloadedBytes = downloadedBytes,
                            uploadedBytes = uploadedBytes,
                        )
                    )
                } catch (error: Throwable) {
                    // A failed stats read must not interrupt a working tunnel.
                } finally {
                    if (core != null) mainHandler.postDelayed(this, 1000)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Подключение…"))
        Seq.setContext(applicationContext)
        Libv2ray.initCoreEnv(filesDir.absolutePath, "")
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> worker.execute { stopTunnel(stopService = true) }
            ACTION_START -> {
                val raw = intent.getStringExtra(EXTRA_CONFIG).orEmpty()
                val requestedProtocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: "vless-reality"
                val splitMode = intent.getStringExtra(EXTRA_SPLIT_MODE) ?: "allTraffic"
                val packages = intent.getStringArrayListExtra(EXTRA_PACKAGES)?.toList().orEmpty()
                AeroXrayState.publish(
                    AeroXraySnapshot(status = "connecting", protocol = requestedProtocol)
                )
                worker.execute {
                    startTunnel(raw, requestedProtocol, splitMode, packages)
                }
            }
        }
        return START_STICKY
    }

    private fun startTunnel(
        rawConfig: String,
        requestedProtocol: String,
        splitMode: String,
        packages: List<String>,
    ) {
        try {
            stopTunnel(stopService = false)
            protocol = requestedProtocol
            val runtimeConfig = XrayConfigFactory.build(rawConfig, requestedProtocol)
            val builder = Builder()
                .setSession("Wesi Aero · ${if (requestedProtocol == "vless-reality") "VLESS" else "VMess"}")
                .setMtu(1500)
                .addAddress("172.31.255.2", 30)
                .addAddress("fd42:42:42::2", 126)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            applyApplicationRouting(builder, splitMode, packages)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            val established = builder.establish()
                ?: throw IllegalStateException("Android failed to create the VPN TUN interface")
            tun = established

            val controller = Libv2ray.newCoreController(CoreCallback())
            core = controller
            controller.startLoop(runtimeConfig, established.fd)
            if (!controller.isRunning) {
                throw IllegalStateException("Xray core did not enter running state")
            }

            connectedAtMs = System.currentTimeMillis()
            downloadedBytes = 0
            uploadedBytes = 0
            AeroXrayState.publish(
                AeroXraySnapshot(
                    status = "connected",
                    protocol = protocol,
                    connectedAtMs = connectedAtMs,
                )
            )
            mainHandler.removeCallbacks(statsTick)
            mainHandler.post(statsTick)
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification("Защищено · ${if (protocol == "vless-reality") "VLESS" else "VMess"}"))
        } catch (error: Throwable) {
            val message = error.message ?: error.javaClass.simpleName
            stopTunnel(stopService = false)
            AeroXrayState.publish(
                AeroXraySnapshot(
                    status = "error",
                    protocol = requestedProtocol,
                    error = "XRAY_START_FAILED: $message",
                )
            )
        }
    }

    private fun applyApplicationRouting(
        builder: Builder,
        splitMode: String,
        packages: List<String>,
    ) {
        when (splitMode) {
            "allowlist" -> {
                if (packages.isEmpty()) {
                    throw IllegalArgumentException("Select at least one application for split routing")
                }
                packages.distinct().forEach { packageName ->
                    if (packageName != this.packageName) {
                        try {
                            builder.addAllowedApplication(packageName)
                        } catch (_: PackageManager.NameNotFoundException) {
                            throw IllegalArgumentException("Application is not installed: $packageName")
                        }
                    }
                }
            }
            "denylist", "allTraffic" -> {
                builder.addDisallowedApplication(packageName)
                if (splitMode == "denylist") {
                    packages.distinct().filter { it != packageName }.forEach { excluded ->
                        try {
                            builder.addDisallowedApplication(excluded)
                        } catch (_: PackageManager.NameNotFoundException) {
                            throw IllegalArgumentException("Application is not installed: $excluded")
                        }
                    }
                }
            }
            else -> throw IllegalArgumentException("Unknown split-routing mode")
        }
    }

    private fun stopTunnel(stopService: Boolean) {
        mainHandler.removeCallbacks(statsTick)
        try {
            core?.stopLoop()
        } catch (_: Throwable) {
        }
        core = null
        try {
            tun?.close()
        } catch (_: Throwable) {
        }
        tun = null
        connectedAtMs = null
        downloadedBytes = 0
        uploadedBytes = 0
        AeroXrayState.publish(AeroXraySnapshot(status = "disconnected", protocol = protocol))
        if (stopService) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onRevoke() {
        worker.execute { stopTunnel(stopService = true) }
        super.onRevoke()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(statsTick)
        try {
            core?.stopLoop()
        } catch (_: Throwable) {
        }
        try {
            tun?.close()
        } catch (_: Throwable) {
        }
        core = null
        tun = null
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "Wesi Aero VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Системное VPN-соединение Wesi Aero"
                setShowBadge(false)
            }
        )
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pending = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Wesi Aero")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pending)
            .build()
    }

    private inner class CoreCallback : CoreCallbackHandler {
        override fun startup(): Long = 0
        override fun shutdown(): Long = 0
        override fun onEmitStatus(code: Long, message: String?): Long = 0
    }
}

internal object XrayConfigFactory {
    fun build(rawConfig: String, protocol: String): String {
        val proxy = when (protocol) {
            "vless-reality" -> buildVless(rawConfig)
            "vmess-xray" -> buildVmess(rawConfig)
            else -> throw IllegalArgumentException("Unsupported Xray protocol: $protocol")
        }

        val tunInbound = JSONObject()
            .put("tag", "tun")
            .put("port", 0)
            .put("protocol", "tun")
            .put(
                "settings",
                JSONObject()
                    .put("name", "wesi0")
                    .put("mtu", 1500)
                    .put("userLevel", 0),
            )
            .put(
                "sniffing",
                JSONObject()
                    .put("enabled", true)
                    .put("destOverride", JSONArray().put("http").put("tls").put("quic")),
            )

        val direct = JSONObject().put("tag", "direct").put("protocol", "freedom")
        val block = JSONObject().put("tag", "block").put("protocol", "blackhole")
        val policy = JSONObject().put(
            "system",
            JSONObject()
                .put("statsOutboundUplink", true)
                .put("statsOutboundDownlink", true),
        )

        return JSONObject()
            .put("log", JSONObject().put("loglevel", "warning"))
            .put("stats", JSONObject())
            .put("policy", policy)
            .put("inbounds", JSONArray().put(tunInbound))
            .put("outbounds", JSONArray().put(proxy).put(direct).put(block))
            .toString()
    }

    private fun buildVless(raw: String): JSONObject {
        val uri = Uri.parse(raw)
        require(uri.scheme == "vless") { "Expected vless:// profile" }
        val host = uri.host?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VLESS host is missing")
        val port = uri.port.takeIf { it in 1..65535 }
            ?: throw IllegalArgumentException("VLESS port is missing")
        val id = uri.userInfo?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VLESS UUID is missing")
        require(uri.getQueryParameter("security")?.lowercase() == "reality") {
            "Wesi Aero requires VLESS + REALITY"
        }
        val serverName = uri.getQueryParameter("sni")?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VLESS REALITY SNI is missing")
        val publicKey = uri.getQueryParameter("pbk")?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VLESS REALITY public key is missing")
        val shortId = uri.getQueryParameter("sid").orEmpty()
        val fingerprint = uri.getQueryParameter("fp")?.takeIf { it.isNotBlank() } ?: "chrome"
        val flow = uri.getQueryParameter("flow")?.takeIf { it.isNotBlank() } ?: "xtls-rprx-vision"
        val spiderX = uri.getQueryParameter("spx")?.let(Uri::decode).orEmpty()

        val user = JSONObject()
            .put("id", id)
            .put("encryption", "none")
            .put("flow", flow)
        val vnext = JSONObject()
            .put("address", host)
            .put("port", port)
            .put("users", JSONArray().put(user))
        val reality = JSONObject()
            .put("serverName", serverName)
            .put("fingerprint", fingerprint)
            .put("publicKey", publicKey)
            .put("shortId", shortId)
            .put("spiderX", spiderX)
        val stream = JSONObject()
            .put("network", "raw")
            .put("security", "reality")
            .put("realitySettings", reality)

        return JSONObject()
            .put("tag", "proxy")
            .put("protocol", "vless")
            .put("settings", JSONObject().put("vnext", JSONArray().put(vnext)))
            .put("streamSettings", stream)
    }

    private fun buildVmess(raw: String): JSONObject {
        require(raw.startsWith("vmess://")) { "Expected vmess:// profile" }
        val payload = raw.removePrefix("vmess://").trim()
        val normalized = payload
            .replace('-', '+')
            .replace('_', '/')
            .let { it + "=".repeat((4 - it.length % 4) % 4) }
        val decoded = String(
            Base64.decode(normalized, Base64.DEFAULT),
            StandardCharsets.UTF_8,
        )
        val profile = JSONObject(decoded)
        val host = profile.optString("add").takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VMess host is missing")
        val port = profile.optString("port").toIntOrNull()?.takeIf { it in 1..65535 }
            ?: throw IllegalArgumentException("VMess port is missing")
        val id = profile.optString("id").takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("VMess UUID is missing")
        val alterId = profile.optString("aid", "0").toIntOrNull() ?: 0
        val security = profile.optString("scy", "auto").ifBlank { "auto" }
        val networkRaw = profile.optString("net", "tcp").lowercase()
        val network = when (networkRaw) {
            "tcp", "raw" -> "raw"
            "ws" -> "ws"
            "grpc" -> "grpc"
            else -> throw IllegalArgumentException("Unsupported VMess transport: $networkRaw")
        }

        val user = JSONObject()
            .put("id", id)
            .put("alterId", alterId)
            .put("security", security)
        val vnext = JSONObject()
            .put("address", host)
            .put("port", port)
            .put("users", JSONArray().put(user))
        val stream = JSONObject().put("network", network)

        when (network) {
            "ws" -> {
                val headers = JSONObject()
                val wsHost = profile.optString("host")
                if (wsHost.isNotBlank()) headers.put("Host", wsHost)
                stream.put(
                    "wsSettings",
                    JSONObject()
                        .put("path", profile.optString("path", "/").ifBlank { "/" })
                        .put("headers", headers),
                )
            }
            "grpc" -> stream.put(
                "grpcSettings",
                JSONObject().put("serviceName", profile.optString("path")),
            )
        }

        val tls = profile.optString("tls").lowercase()
        if (tls == "tls") {
            stream.put("security", "tls")
            val sni = profile.optString("sni").ifBlank {
                profile.optString("host").ifBlank { host }
            }
            stream.put(
                "tlsSettings",
                JSONObject()
                    .put("serverName", sni)
                    .put("allowInsecure", false),
            )
        } else {
            stream.put("security", "none")
        }

        return JSONObject()
            .put("tag", "proxy")
            .put("protocol", "vmess")
            .put("settings", JSONObject().put("vnext", JSONArray().put(vnext)))
            .put("streamSettings", stream)
    }
}
''',
        encoding="utf-8",
    )


def main() -> None:
    if not GRADLE.is_file() or not MANIFEST.is_file():
        raise SystemExit("Generate the Android Flutter platform before configuring Xray")
    if not AAR.is_file():
        raise SystemExit(
            f"Missing {AAR}. Download the pinned AndroidLibXrayLite libv2ray.aar before running this script."
        )
    KOTLIN_DIR.mkdir(parents=True, exist_ok=True)
    patch_gradle()
    patch_manifest()
    write_main_activity()
    write_xray_service()
    print("Configured native Android Xray TUN backend for VLESS/REALITY and VMess")


if __name__ == "__main__":
    main()
