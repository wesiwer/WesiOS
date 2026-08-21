#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
KOTLIN_DIR = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero"
SERVICE = KOTLIN_DIR / "AeroSingBoxVpnService.kt"
AAR = ROOT / "android/app/libs/libbox.aar"


def patch_gradle() -> None:
    if not AAR.is_file() or AAR.stat().st_size < 5_000_000:
        raise SystemExit("Build android/app/libs/libbox.aar before configuring sing-box")
    text = GRADLE.read_text(encoding="utf-8")
    marker = 'implementation(files("libs/libbox.aar"))'
    if marker not in text:
        text = text.rstrip() + f'\n\ndependencies {{\n    {marker}\n}}\n'
    GRADLE.write_text(text, encoding="utf-8")


def patch_manifest() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    ]
    insertion = "\n    ".join(item for item in permissions if item not in text)
    if insertion:
        root = re.search(r"<manifest[^>]*>", text)
        if not root:
            raise SystemExit("Android manifest root not found")
        pos = root.end()
        text = text[:pos] + "\n    " + insertion + text[pos:]

    service = '''
        <service
            android:name=".AeroSingBoxVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="false"
            android:foregroundServiceType="specialUse"
            android:stopWithTask="false">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="vpn" />
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
'''
    if 'android:name=".AeroSingBoxVpnService"' not in text:
        text = text.replace("</application>", service + "    </application>", 1)
    MANIFEST.write_text(text, encoding="utf-8")


def write_service() -> None:
    KOTLIN_DIR.mkdir(parents=True, exist_ok=True)
    SERVICE.write_text(
        r'''package com.wesi.wesi_aero

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import android.util.Base64
import go.Seq
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification as BoxNotification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.security.KeyStore
import java.util.Collections
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.nekohasekai.libbox.NetworkInterface as BoxNetworkInterface

internal data class AeroSingBoxSnapshot(
    val status: String = "disconnected",
    val protocol: String = "vless-reality",
    val connectedAtMs: Long? = null,
    val error: String? = null,
)

internal object AeroSingBoxState {
    @Volatile private var snapshot = AeroSingBoxSnapshot()
    @Volatile var listener: ((AeroSingBoxSnapshot) -> Unit)? = null

    fun current(): AeroSingBoxSnapshot = snapshot

    fun publish(next: AeroSingBoxSnapshot) {
        snapshot = next
        listener?.invoke(next)
    }
}

class AeroSingBoxVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    companion object {
        private const val ACTION_START = "com.wesi.aero.SINGBOX_START"
        private const val ACTION_STOP = "com.wesi.aero.SINGBOX_STOP"
        private const val EXTRA_PROTOCOL = "protocol"
        private const val EXTRA_CONFIG = "config"
        private const val EXTRA_SPLIT_MODE = "splitMode"
        private const val EXTRA_PACKAGES = "packages"
        private const val NOTIFICATION_CHANNEL = "wesi_aero_singbox_vpn"
        private const val NOTIFICATION_ID = 22082
        @Volatile private var libboxInitialized = false

        fun start(
            context: Context,
            protocol: String,
            rawConfig: String,
            splitMode: String,
            appPackages: List<String>,
        ) {
            val intent = Intent(context, AeroSingBoxVpnService::class.java)
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
            context.startService(
                Intent(context, AeroSingBoxVpnService::class.java).setAction(ACTION_STOP)
            )
        }
    }

    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var connectivity: ConnectivityManager
    private var commandServer: CommandServer? = null
    private var vpnInterface: ParcelFileDescriptor? = null
    private var defaultNetworkListener: InterfaceUpdateListener? = null
    private var defaultNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var currentConfig: String? = null
    private var currentProtocol = "vless-reality"
    private var currentSplitMode = "allTraffic"
    private var currentPackages: List<String> = emptyList()

    override fun onCreate() {
        super.onCreate()
        connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Подготовка sing-box…"))
        Seq.setContext(applicationContext)
        initializeLibbox()
    }

    private fun initializeLibbox() {
        if (libboxInitialized) return
        synchronized(AeroSingBoxVpnService::class.java) {
            if (libboxInitialized) return
            val base = filesDir.apply { mkdirs() }
            val working = (getExternalFilesDir(null) ?: filesDir).apply { mkdirs() }
            val temp = cacheDir.apply { mkdirs() }
            Libbox.setup(
                SetupOptions().apply {
                    basePath = base.absolutePath
                    workingPath = working.absolutePath
                    tempPath = temp.absolutePath
                    fixAndroidStack = true
                    commandServerListenPort = 0
                    commandServerSecret = ""
                    logMaxLines = 300
                    debug = false
                }
            )
            libboxInitialized = true
        }
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> worker.execute { stopTunnel(stopService = true) }
            ACTION_START -> {
                val raw = intent.getStringExtra(EXTRA_CONFIG).orEmpty()
                val protocol = intent.getStringExtra(EXTRA_PROTOCOL) ?: "vless-reality"
                val splitMode = intent.getStringExtra(EXTRA_SPLIT_MODE) ?: "allTraffic"
                val packages = intent.getStringArrayListExtra(EXTRA_PACKAGES)?.toList().orEmpty()
                AeroSingBoxState.publish(
                    AeroSingBoxSnapshot(status = "connecting", protocol = protocol)
                )
                worker.execute { startTunnel(raw, protocol, splitMode, packages) }
            }
        }
        return START_NOT_STICKY
    }

    private fun startTunnel(
        rawConfig: String,
        protocol: String,
        splitMode: String,
        packages: List<String>,
    ) {
        try {
            stopTunnel(stopService = false)
            val config = SingBoxConfigFactory.build(rawConfig, protocol, splitMode, packages, packageName)
            Libbox.checkConfig(config)
            currentConfig = config
            currentProtocol = protocol
            currentSplitMode = splitMode
            currentPackages = packages

            val server = CommandServer(this, this)
            server.start()
            server.startOrReloadService(config, OverrideOptions())
            commandServer = server
            val connectedAt = System.currentTimeMillis()
            AeroSingBoxState.publish(
                AeroSingBoxSnapshot(
                    status = "connected",
                    protocol = protocol,
                    connectedAtMs = connectedAt,
                )
            )
            getSystemService(NotificationManager::class.java).notify(
                NOTIFICATION_ID,
                buildNotification("Защищено · sing-box · ${SingBoxConfigFactory.title(protocol)}"),
            )
        } catch (error: Throwable) {
            val message = error.message ?: error.javaClass.simpleName
            stopTunnel(stopService = false)
            AeroSingBoxState.publish(
                AeroSingBoxSnapshot(
                    status = "error",
                    protocol = protocol,
                    error = "SINGBOX_START_FAILED: $message",
                )
            )
        }
    }

    private fun stopTunnel(stopService: Boolean) {
        try {
            commandServer?.closeService()
        } catch (_: Throwable) {
        }
        try {
            commandServer?.close()
        } catch (_: Throwable) {
        }
        commandServer = null
        try {
            vpnInterface?.close()
        } catch (_: Throwable) {
        }
        vpnInterface = null
        currentConfig = null
        closeDefaultNetworkCallback()
        AeroSingBoxState.publish(
            AeroSingBoxSnapshot(status = "disconnected", protocol = currentProtocol)
        )
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
        stopTunnel(stopService = false)
        worker.shutdownNow()
        super.onDestroy()
    }

    // CommandServerHandler
    override fun serviceStop() {
        worker.execute { stopTunnel(stopService = true) }
    }

    override fun serviceReload() {
        val config = currentConfig ?: return
        worker.execute {
            try {
                commandServer?.startOrReloadService(config, OverrideOptions())
            } catch (error: Throwable) {
                AeroSingBoxState.publish(
                    AeroSingBoxSnapshot(
                        status = "error",
                        protocol = currentProtocol,
                        error = "SINGBOX_RELOAD_FAILED: ${error.message ?: error.javaClass.simpleName}",
                    )
                )
            }
        }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        available = false
        enabled = false
    }

    override fun setSystemProxyEnabled(enabled: Boolean) {
        // Wesi Aero does not expose Android's global HTTP proxy. TUN stays authoritative.
    }

    override fun writeDebugMessage(message: String?) {
        // Intentionally not persisted: VPN URLs, DNS names and packet metadata are not logged.
    }

    // PlatformInterface
    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!protect(fd)) error("android: failed to protect sing-box outbound socket")
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing VPN permission")
        val builder = Builder()
            .setSession("Wesi Aero · sing-box")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val inet4 = options.inet4Address
        var hasInet4 = false
        while (inet4.hasNext()) {
            val address = inet4.next()
            builder.addAddress(address.address(), address.prefix())
            hasInet4 = true
        }
        val inet6 = options.inet6Address
        var hasInet6 = false
        while (inet6.hasNext()) {
            val address = inet6.next()
            builder.addAddress(address.address(), address.prefix())
            hasInet6 = true
        }

        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress.value)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4Routes = options.inet4RouteAddress
                if (inet4Routes.hasNext()) {
                    while (inet4Routes.hasNext()) {
                        val route = inet4Routes.next()
                        builder.addRoute(android.net.IpPrefix("${route.address()}/${route.prefix()}"))
                    }
                } else if (hasInet4) {
                    builder.addRoute("0.0.0.0", 0)
                }
                val inet6Routes = options.inet6RouteAddress
                if (inet6Routes.hasNext()) {
                    while (inet6Routes.hasNext()) {
                        val route = inet6Routes.next()
                        builder.addRoute(android.net.IpPrefix("${route.address()}/${route.prefix()}"))
                    }
                } else if (hasInet6) {
                    builder.addRoute("::", 0)
                }
                val exclude4 = options.inet4RouteExcludeAddress
                while (exclude4.hasNext()) {
                    val route = exclude4.next()
                    builder.excludeRoute(android.net.IpPrefix("${route.address()}/${route.prefix()}"))
                }
                val exclude6 = options.inet6RouteExcludeAddress
                while (exclude6.hasNext()) {
                    val route = exclude6.next()
                    builder.excludeRoute(android.net.IpPrefix("${route.address()}/${route.prefix()}"))
                }
            } else {
                val range4 = options.inet4RouteRange
                while (range4.hasNext()) {
                    val route = range4.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                val range6 = options.inet6RouteRange
                while (range6.hasNext()) {
                    val route = range6.next()
                    builder.addRoute(route.address(), route.prefix())
                }
            }

            val include = options.includePackage
            var included = false
            while (include.hasNext()) {
                val packageName = include.next()
                if (packageName == this.packageName) continue
                try {
                    builder.addAllowedApplication(packageName)
                    included = true
                } catch (_: PackageManager.NameNotFoundException) {
                }
            }
            if (!included) {
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: PackageManager.NameNotFoundException) {
                }
                val exclude = options.excludePackage
                while (exclude.hasNext()) {
                    val packageName = exclude.next()
                    if (packageName == this.packageName) continue
                    try {
                        builder.addDisallowedApplication(packageName)
                    } catch (_: PackageManager.NameNotFoundException) {
                    }
                }
            }
        }

        val pfd = builder.establish()
            ?: error("android: failed to establish sing-box VPN interface")
        vpnInterface?.close()
        vpnInterface = pfd
        return pfd.fd
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error("android: connection owner API requires Android Q")
        }
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress ?: "0.0.0.0", sourcePort),
            InetSocketAddress(destinationAddress ?: "0.0.0.0", destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        val owner = ConnectionOwner()
        owner.userId = uid
        val packages = packageManager.getPackagesForUid(uid)
        owner.userName = packages?.firstOrNull() ?: ""
        owner.setAndroidPackageNames(StringArray(packages?.asIterable()?.iterator() ?: emptyList<String>().iterator()))
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        defaultNetworkListener = listener
        closeDefaultNetworkCallback()
        defaultNetworkListener = listener
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publishDefaultNetwork(network)
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                publishDefaultNetwork(network)
            override fun onLost(network: Network) {
                connectivity.activeNetwork?.let(::publishDefaultNetwork)
            }
        }
        defaultNetworkCallback = callback
        connectivity.registerDefaultNetworkCallback(callback)
        connectivity.activeNetwork?.let(::publishDefaultNetwork)
    }

    private fun publishDefaultNetwork(network: Network) {
        val listener = defaultNetworkListener ?: return
        val properties = connectivity.getLinkProperties(network) ?: return
        val name = properties.interfaceName ?: return
        val index = try {
            NetworkInterface.getByName(name)?.index ?: 0
        } catch (_: Throwable) {
            0
        }
        val capabilities = connectivity.getNetworkCapabilities(network)
        val expensive = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
        listener.updateDefaultInterface(name, index, expensive, false)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        closeDefaultNetworkCallback()
    }

    private fun closeDefaultNetworkCallback() {
        val callback = defaultNetworkCallback
        if (callback != null) {
            try {
                connectivity.unregisterNetworkCallback(callback)
            } catch (_: Throwable) {
            }
        }
        defaultNetworkCallback = null
        defaultNetworkListener = null
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val javaInterfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
        val values = mutableListOf<BoxNetworkInterface>()
        for (network in connectivity.allNetworks) {
            val props = connectivity.getLinkProperties(network) ?: continue
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            val name = props.interfaceName ?: continue
            val system = javaInterfaces.firstOrNull { it.name == name } ?: continue
            val item = BoxNetworkInterface()
            item.name = name
            item.index = system.index
            item.mtu = runCatching { system.mtu }.getOrDefault(1500)
            item.addresses = StringArray(system.interfaceAddresses.map { it.toPrefix() }.iterator())
            item.dnsServer = StringArray(props.dnsServers.mapNotNull { it.hostAddress }.iterator())
            item.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (system.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (system.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (system.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            item.flags = flags
            item.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            values.add(item)
        }
        return InterfaceArray(values.iterator())
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun systemCertificates(): StringIterator {
        val values = mutableListOf<String>()
        val store = KeyStore.getInstance("AndroidCAStore")
        store.load(null, null)
        val aliases = store.aliases()
        while (aliases.hasMoreElements()) {
            val certificate = store.getCertificate(aliases.nextElement()) ?: continue
            values.add(
                "-----BEGIN CERTIFICATE-----\n" +
                    Base64.encodeToString(certificate.encoded, Base64.NO_WRAP) +
                    "\n-----END CERTIFICATE-----"
            )
        }
        return StringArray(values.iterator())
    }

    override fun clearDNSCache() {
    }

    override fun sendNotification(notification: BoxNotification?) {
        // Core notifications are deliberately not surfaced; the foreground VPN notification is authoritative.
    }

    private class InterfaceArray(
        private val iterator: Iterator<BoxNetworkInterface>,
    ) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): BoxNetworkInterface = iterator.next()
    }

    internal class StringArray(
        private val iterator: Iterator<String>,
    ) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }

    private fun InterfaceAddress.toPrefix(): String = if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "Wesi Aero sing-box VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Системный VPN-движок sing-box"
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
}

internal object SingBoxConfigFactory {
    fun title(protocol: String): String = when (protocol) {
        "vless-reality" -> "VLESS"
        "vmess" -> "VMess"
        "trojan" -> "Trojan"
        "shadowsocks" -> "Shadowsocks"
        "hysteria2" -> "Hysteria2"
        "tuic" -> "TUIC"
        "wireguard" -> "WireGuard"
        else -> protocol
    }

    fun build(
        rawConfig: String,
        protocol: String,
        splitMode: String,
        packages: List<String>,
        selfPackage: String,
    ): String {
        val outbound = when (protocol) {
            "vless-reality" -> buildVless(rawConfig)
            "vmess", "vmess-xray" -> buildVmess(rawConfig)
            "trojan" -> buildTrojan(rawConfig)
            "shadowsocks" -> buildShadowsocks(rawConfig)
            "hysteria2" -> buildHysteria2(rawConfig)
            "tuic" -> buildTuic(rawConfig)
            else -> throw IllegalArgumentException("sing-box does not support Wesi protocol: $protocol")
        }.put("tag", "proxy")

        val tun = JSONObject()
            .put("type", "tun")
            .put("tag", "tun-in")
            .put("address", JSONArray().put("172.19.0.1/30"))
            .put("mtu", 1500)
            .put("auto_route", true)
            .put("strict_route", true)
            .put("stack", "mixed")

        val cleanPackages = packages.filter { it.isNotBlank() && it != selfPackage }.distinct()
        when (splitMode) {
            "allowlist" -> {
                if (cleanPackages.isEmpty()) throw IllegalArgumentException("Select at least one application")
                tun.put("include_package", JSONArray(cleanPackages))
            }
            "denylist" -> tun.put(
                "exclude_package",
                JSONArray(listOf(selfPackage) + cleanPackages),
            )
            "allTraffic" -> tun.put("exclude_package", JSONArray().put(selfPackage))
            else -> throw IllegalArgumentException("Unknown split-routing mode")
        }

        val dns = JSONObject()
            .put(
                "servers",
                JSONArray().put(
                    JSONObject()
                        .put("type", "udp")
                        .put("tag", "dns-proxy")
                        .put("server", "1.1.1.1")
                        .put("server_port", 53)
                        .put("detour", "proxy")
                )
            )
            .put("final", "dns-proxy")
            .put("strategy", "ipv4_only")
            .put("cache_capacity", 4096)

        val route = JSONObject()
            .put(
                "rules",
                JSONArray().put(
                    JSONObject()
                        .put("port", 53)
                        .put("action", "hijack-dns")
                )
            )
            .put("final", "proxy")
            .put("auto_detect_interface", true)

        return JSONObject()
            .put("log", JSONObject().put("level", "warn").put("timestamp", false))
            .put("dns", dns)
            .put("inbounds", JSONArray().put(tun))
            .put(
                "outbounds",
                JSONArray()
                    .put(outbound)
                    .put(JSONObject().put("type", "direct").put("tag", "direct"))
            )
            .put("route", route)
            .toString()
    }

    private fun buildVless(raw: String): JSONObject {
        val uri = android.net.Uri.parse(raw)
        require(uri.scheme == "vless") { "Expected vless:// profile" }
        val server = uri.host?.takeIf { it.isNotBlank() } ?: error("VLESS server missing")
        val port = uri.port.takeIf { it in 1..65535 } ?: error("VLESS port missing")
        val uuid = uri.userInfo?.takeIf { it.isNotBlank() } ?: error("VLESS UUID missing")
        require(uri.getQueryParameter("security")?.lowercase() == "reality") {
            "VLESS profile must use REALITY"
        }
        val serverName = uri.getQueryParameter("sni")?.takeIf { it.isNotBlank() }
            ?: error("VLESS SNI missing")
        val publicKey = uri.getQueryParameter("pbk")?.takeIf { it.isNotBlank() }
            ?: error("VLESS REALITY public key missing")
        val shortId = uri.getQueryParameter("sid") ?: ""
        val fingerprint = uri.getQueryParameter("fp")?.takeIf { it.isNotBlank() } ?: "chrome"
        val flow = uri.getQueryParameter("flow")?.takeIf { it.isNotBlank() }

        return JSONObject()
            .put("type", "vless")
            .put("server", server)
            .put("server_port", port)
            .put("uuid", uuid)
            .apply { if (flow != null) put("flow", flow) }
            .put(
                "tls",
                JSONObject()
                    .put("enabled", true)
                    .put("server_name", serverName)
                    .put(
                        "utls",
                        JSONObject().put("enabled", true).put("fingerprint", fingerprint),
                    )
                    .put(
                        "reality",
                        JSONObject()
                            .put("enabled", true)
                            .put("public_key", publicKey)
                            .put("short_id", shortId),
                    ),
            )
    }

    private fun buildVmess(raw: String): JSONObject {
        require(raw.startsWith("vmess://")) { "Expected vmess:// profile" }
        val encoded = raw.removePrefix("vmess://").trim()
        val decoded = String(
            Base64.decode(normalizeBase64(encoded), Base64.DEFAULT),
            Charsets.UTF_8,
        )
        val profile = JSONObject(decoded)
        val server = profile.optString("add").takeIf { it.isNotBlank() }
            ?: error("VMess server missing")
        val port = profile.optString("port").toIntOrNull()
            ?: error("VMess port missing")
        val uuid = profile.optString("id").takeIf { it.isNotBlank() }
            ?: error("VMess UUID missing")
        val security = profile.optString("scy").takeIf { it.isNotBlank() } ?: "auto"
        val network = profile.optString("net").takeIf { it.isNotBlank() } ?: "tcp"

        val outbound = JSONObject()
            .put("type", "vmess")
            .put("server", server)
            .put("server_port", port)
            .put("uuid", uuid)
            .put("security", security)
            .put("alter_id", profile.optString("aid", "0").toIntOrNull() ?: 0)

        when (network) {
            "ws" -> outbound.put(
                "transport",
                JSONObject()
                    .put("type", "ws")
                    .put("path", profile.optString("path", "/"))
                    .apply {
                        val host = profile.optString("host")
                        if (host.isNotBlank()) {
                            put("headers", JSONObject().put("Host", host))
                        }
                    },
            )
            "grpc" -> outbound.put(
                "transport",
                JSONObject()
                    .put("type", "grpc")
                    .put("service_name", profile.optString("path")),
            )
            "tcp", "raw", "" -> Unit
            else -> throw IllegalArgumentException("Unsupported VMess transport: $network")
        }
        if (profile.optString("tls").equals("tls", ignoreCase = true)) {
            outbound.put(
                "tls",
                JSONObject()
                    .put("enabled", true)
                    .put(
                        "server_name",
                        profile.optString("sni").takeIf { it.isNotBlank() }
                            ?: profile.optString("host").takeIf { it.isNotBlank() }
                            ?: server,
                    ),
            )
        }
        return outbound
    }

    private fun buildTrojan(raw: String): JSONObject {
        val uri = android.net.Uri.parse(raw)
        require(uri.scheme == "trojan") { "Expected trojan:// profile" }
        val server = uri.host ?: error("Trojan server missing")
        val port = uri.port.takeIf { it > 0 } ?: error("Trojan port missing")
        val password = uri.userInfo?.takeIf { it.isNotBlank() } ?: error("Trojan password missing")
        val sni = uri.getQueryParameter("sni") ?: server
        return JSONObject()
            .put("type", "trojan")
            .put("server", server)
            .put("server_port", port)
            .put("password", password)
            .put("tls", JSONObject().put("enabled", true).put("server_name", sni))
    }

    private fun buildShadowsocks(raw: String): JSONObject {
        val uri = android.net.Uri.parse(raw)
        require(uri.scheme == "ss") { "Expected ss:// profile" }
        var server = uri.host
        var port = uri.port
        var credentials = uri.userInfo.orEmpty()
        if (server.isNullOrBlank() || port <= 0) {
            val payload = raw.removePrefix("ss://").substringBefore('#').substringBefore('?')
            val decoded = String(Base64.decode(normalizeBase64(payload), Base64.DEFAULT), Charsets.UTF_8)
            val at = decoded.lastIndexOf('@')
            require(at > 0) { "Invalid Shadowsocks profile" }
            credentials = decoded.substring(0, at)
            val endpoint = decoded.substring(at + 1)
            val colon = endpoint.lastIndexOf(':')
            require(colon > 0) { "Invalid Shadowsocks endpoint" }
            server = endpoint.substring(0, colon)
            port = endpoint.substring(colon + 1).toInt()
        } else {
            credentials = String(
                Base64.decode(normalizeBase64(credentials), Base64.DEFAULT),
                Charsets.UTF_8,
            )
        }
        val split = credentials.indexOf(':')
        require(split > 0) { "Shadowsocks method/password missing" }
        return JSONObject()
            .put("type", "shadowsocks")
            .put("server", server)
            .put("server_port", port)
            .put("method", credentials.substring(0, split))
            .put("password", credentials.substring(split + 1))
    }

    private fun buildHysteria2(raw: String): JSONObject {
        val uri = android.net.Uri.parse(raw)
        require(uri.scheme == "hysteria2" || uri.scheme == "hy2") { "Expected hysteria2:// profile" }
        val server = uri.host ?: error("Hysteria2 server missing")
        val port = uri.port.takeIf { it > 0 } ?: error("Hysteria2 port missing")
        val password = uri.userInfo?.takeIf { it.isNotBlank() } ?: error("Hysteria2 password missing")
        val sni = uri.getQueryParameter("sni") ?: server
        return JSONObject()
            .put("type", "hysteria2")
            .put("server", server)
            .put("server_port", port)
            .put("password", password)
            .put("tls", JSONObject().put("enabled", true).put("server_name", sni))
    }

    private fun buildTuic(raw: String): JSONObject {
        val uri = android.net.Uri.parse(raw)
        require(uri.scheme == "tuic") { "Expected tuic:// profile" }
        val server = uri.host ?: error("TUIC server missing")
        val port = uri.port.takeIf { it > 0 } ?: error("TUIC port missing")
        val user = uri.userInfo.orEmpty().split(':', limit = 2)
        require(user.size == 2 && user[0].isNotBlank() && user[1].isNotBlank()) {
            "TUIC UUID/password missing"
        }
        val sni = uri.getQueryParameter("sni") ?: server
        return JSONObject()
            .put("type", "tuic")
            .put("server", server)
            .put("server_port", port)
            .put("uuid", user[0])
            .put("password", user[1])
            .put("congestion_control", uri.getQueryParameter("congestion_control") ?: "bbr")
            .put("tls", JSONObject().put("enabled", true).put("server_name", sni))
    }

    private fun normalizeBase64(value: String): String {
        val normalized = value.replace('-', '+').replace('_', '/')
        val padding = (4 - normalized.length % 4) % 4
        return normalized + "=".repeat(padding)
    }
}
''',
        encoding="utf-8",
    )


def main() -> None:
    patch_gradle()
    patch_manifest()
    write_service()
    text = SERVICE.read_text(encoding="utf-8")
    required = [
        'class AeroSingBoxVpnService : VpnService(), PlatformInterface, CommandServerHandler',
        'server.startOrReloadService(config, OverrideOptions())',
        'override fun autoDetectInterfaceControl(fd: Int)',
        'override fun openTun(options: TunOptions): Int',
        'Libbox.checkConfig(config)',
        '"hysteria2" -> buildHysteria2(rawConfig)',
        '"tuic" -> buildTuic(rawConfig)',
    ]
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"sing-box Android service verification failed: {missing}")
    print("Configured independent Android sing-box VPN service")


if __name__ == "__main__":
    main()
