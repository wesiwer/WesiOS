#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt"
MAIN = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one patch anchor, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    if not SERVICE.exists() or not MAIN.exists():
        raise SystemExit("Generate Android Xray integration before hardening it")

    text = SERVICE.read_text(encoding="utf-8")

    # v2rayNG's working Android built-in-TUN path does not enable IPv6 unless
    # IPv6 is explicitly requested. Wesi Relay is currently live-verified for
    # IPv4 egress only, so capture only IPv4 here. Android blocks the omitted
    # address family instead of leaking it outside the VPN.
    text = text.replace('                .addAddress("fd42:42:42::2", 126)\n', "", 1)
    text = text.replace('                .addRoute("::", 0)\n', "", 1)

    text = replace_once(
        text,
        "import android.net.Uri\nimport android.net.VpnService\n",
        "import android.net.ConnectivityManager\n"
        "import android.net.Network\n"
        "import android.net.NetworkCapabilities\n"
        "import android.net.NetworkRequest\n"
        "import android.net.Uri\n"
        "import android.net.VpnService\n",
        "network imports",
    )

    text = replace_once(
        text,
        "    private val worker: ExecutorService = Executors.newSingleThreadExecutor()\n"
        "    private val mainHandler = Handler(Looper.getMainLooper())\n"
        "    private var core: CoreController? = null\n",
        "    private val worker: ExecutorService = Executors.newSingleThreadExecutor()\n"
        "    private val mainHandler = Handler(Looper.getMainLooper())\n"
        "    private lateinit var connectivityManager: ConnectivityManager\n"
        "    @Volatile private var underlyingNetwork: Network? = null\n"
        "    private var networkCallbackRegistered = false\n"
        "    private val networkCallback = object : ConnectivityManager.NetworkCallback() {\n"
        "        override fun onAvailable(network: Network) {\n"
        "            val caps = connectivityManager.getNetworkCapabilities(network) ?: return\n"
        "            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||\n"
        "                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return\n"
        "            underlyingNetwork = network\n"
        "            applyUnderlyingNetwork(network)\n"
        "        }\n"
        "\n"
        "        override fun onLost(network: Network) {\n"
        "            if (underlyingNetwork != network) return\n"
        "            underlyingNetwork = null\n"
        "            bindBestUnderlyingNetwork()\n"
        "        }\n"
        "    }\n"
        "    private var core: CoreController? = null\n",
        "underlying-network fields",
    )

    # Initialise ConnectivityManager in onCreate, but register the callback only
    # after Xray has successfully consumed the TUN fd. This mirrors v2rayNG's
    # lifecycle and avoids changing network hints while the VPN is being built.
    text = replace_once(
        text,
        "        Seq.setContext(applicationContext)\n"
        "        Libv2ray.initCoreEnv(filesDir.absolutePath, \"\")\n",
        "        Seq.setContext(applicationContext)\n"
        "        Libv2ray.initCoreEnv(filesDir.absolutePath, \"\")\n"
        "        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager\n",
        "service connectivity init",
    )

    text = replace_once(
        text,
        "            controller.startLoop(runtimeConfig, established.fd)\n"
        "            if (!controller.isRunning) {\n"
        "                throw IllegalStateException(\"Xray core did not enter running state\")\n"
        "            }\n\n"
        "            connectedAtMs = System.currentTimeMillis()\n",
        "            controller.startLoop(runtimeConfig, established.fd)\n"
        "            if (!controller.isRunning) {\n"
        "                throw IllegalStateException(\"Xray core did not enter running state\")\n"
        "            }\n"
        "            startUnderlyingNetworkMonitor()\n"
        "            // Startup must never depend on an external probe. In particular, do not\n"
        "            // execute measureDelay(\"https://cp.cloudflare.com/generate_204\") here.\n\n"
        "            connectedAtMs = System.currentTimeMillis()\n",
        "post-core network monitor",
    )

    # Align the built-in Xray TUN policy with the proven Android v2rayNG
    # template from the same Xray generation: level 8 with explicit timeouts,
    # xray0 TUN name, and an auxiliary local SOCKS inbound for diagnostics.
    text = replace_once(
        text,
        "        val tunInbound = JSONObject()\n"
        "            .put(\"tag\", \"tun\")\n"
        "            .put(\"port\", 0)\n"
        "            .put(\"protocol\", \"tun\")\n"
        "            .put(\n"
        "                \"settings\",\n"
        "                JSONObject()\n"
        "                    .put(\"name\", \"wesi0\")\n"
        "                    .put(\"mtu\", 1500)\n"
        "                    .put(\"userLevel\", 0),\n"
        "            )\n"
        "            .put(\n"
        "                \"sniffing\",\n"
        "                JSONObject()\n"
        "                    .put(\"enabled\", true)\n"
        "                    .put(\"destOverride\", JSONArray().put(\"http\").put(\"tls\").put(\"quic\")),\n"
        "            )\n",
        "        val socksInbound = JSONObject()\n"
        "            .put(\"tag\", \"socks\")\n"
        "            .put(\"listen\", \"127.0.0.1\")\n"
        "            .put(\"port\", 10808)\n"
        "            .put(\"protocol\", \"socks\")\n"
        "            .put(\n"
        "                \"settings\",\n"
        "                JSONObject()\n"
        "                    .put(\"auth\", \"noauth\")\n"
        "                    .put(\"udp\", true)\n"
        "                    .put(\"userLevel\", 8),\n"
        "            )\n"
        "            .put(\n"
        "                \"sniffing\",\n"
        "                JSONObject()\n"
        "                    .put(\"enabled\", true)\n"
        "                    .put(\"destOverride\", JSONArray().put(\"http\").put(\"tls\")),\n"
        "            )\n\n"
        "        val tunInbound = JSONObject()\n"
        "            .put(\"tag\", \"tun\")\n"
        "            .put(\"protocol\", \"tun\")\n"
        "            .put(\n"
        "                \"settings\",\n"
        "                JSONObject()\n"
        "                    .put(\"name\", \"xray0\")\n"
        "                    .put(\"MTU\", 1500)\n"
        "                    .put(\"userLevel\", 8),\n"
        "            )\n"
        "            .put(\n"
        "                \"sniffing\",\n"
        "                JSONObject()\n"
        "                    .put(\"enabled\", true)\n"
        "                    .put(\"destOverride\", JSONArray().put(\"http\").put(\"tls\")),\n"
        "            )\n",
        "v2rayNG-compatible inbounds",
    )

    text = replace_once(
        text,
        "        val direct = JSONObject().put(\"tag\", \"direct\").put(\"protocol\", \"freedom\")\n",
        "        val direct = JSONObject()\n"
        "            .put(\"tag\", \"direct\")\n"
        "            .put(\"protocol\", \"freedom\")\n"
        "            .put(\"settings\", JSONObject().put(\"domainStrategy\", \"UseIP\"))\n",
        "direct outbound settings",
    )

    text = replace_once(
        text,
        "        val policy = JSONObject().put(\n"
        "            \"system\",\n"
        "            JSONObject()\n"
        "                .put(\"statsOutboundUplink\", true)\n"
        "                .put(\"statsOutboundDownlink\", true),\n"
        "        )\n",
        "        val policy = JSONObject()\n"
        "            .put(\n"
        "                \"levels\",\n"
        "                JSONObject().put(\n"
        "                    \"8\",\n"
        "                    JSONObject()\n"
        "                        .put(\"handshake\", 4)\n"
        "                        .put(\"connIdle\", 300)\n"
        "                        .put(\"uplinkOnly\", 1)\n"
        "                        .put(\"downlinkOnly\", 1),\n"
        "                ),\n"
        "            )\n"
        "            .put(\n"
        "                \"system\",\n"
        "                JSONObject()\n"
        "                    .put(\"statsInboundUplink\", true)\n"
        "                    .put(\"statsInboundDownlink\", true)\n"
        "                    .put(\"statsOutboundUplink\", true)\n"
        "                    .put(\"statsOutboundDownlink\", true),\n"
        "            )\n",
        "Xray policy level 8",
    )

    text = replace_once(
        text,
        "            .put(\"policy\", policy)\n"
        "            .put(\"inbounds\", JSONArray().put(tunInbound))\n",
        "            .put(\"policy\", policy)\n"
        "            .put(\"dns\", JSONObject().put(\"hosts\", JSONObject()).put(\"servers\", JSONArray()))\n"
        "            .put(\"inbounds\", JSONArray().put(socksInbound).put(tunInbound))\n",
        "runtime DNS and inbounds",
    )

    # Route Android TUN traffic explicitly through the selected proxy. The local
    # SOCKS inbound is left on the normal first-outbound path, which is also proxy.
    text = replace_once(
        text,
        "            .put(\"outbounds\", JSONArray().put(proxy).put(direct).put(block))\n"
        "            .toString()\n",
        "            .put(\"outbounds\", JSONArray().put(proxy).put(direct).put(block))\n"
        "            .put(\n"
        "                \"routing\",\n"
        "                JSONObject()\n"
        "                    .put(\"domainStrategy\", \"AsIs\")\n"
        "                    .put(\n"
        "                        \"rules\",\n"
        "                        JSONArray().put(\n"
        "                            JSONObject()\n"
        "                                .put(\"type\", \"field\")\n"
        "                                .put(\"inboundTag\", JSONArray().put(\"tun\"))\n"
        "                                .put(\"outboundTag\", \"proxy\"),\n"
        "                        ),\n"
        "                    ),\n"
        "            )\n"
        "            .toString()\n",
        "explicit TUN routing",
    )

    text = replace_once(
        text,
        "        val user = JSONObject()\n"
        "            .put(\"id\", id)\n"
        "            .put(\"encryption\", \"none\")\n",
        "        val user = JSONObject()\n"
        "            .put(\"id\", id)\n"
        "            .put(\"level\", 8)\n"
        "            .put(\"encryption\", \"none\")\n",
        "VLESS user policy level",
    )
    text = replace_once(
        text,
        "        val user = JSONObject()\n"
        "            .put(\"id\", id)\n"
        "            .put(\"alterId\", alterId)\n",
        "        val user = JSONObject()\n"
        "            .put(\"id\", id)\n"
        "            .put(\"level\", 8)\n"
        "            .put(\"alterId\", alterId)\n",
        "VMess user policy level",
    )

    methods = '''    private fun startUnderlyingNetworkMonitor() {
        if (networkCallbackRegistered) return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        connectivityManager.registerNetworkCallback(request, networkCallback)
        networkCallbackRegistered = true
        bindBestUnderlyingNetwork()
    }

    private fun stopUnderlyingNetworkMonitor() {
        if (networkCallbackRegistered) {
            try {
                connectivityManager.unregisterNetworkCallback(networkCallback)
            } catch (_: Throwable) {
            }
            networkCallbackRegistered = false
        }
        underlyingNetwork = null
        try {
            setUnderlyingNetworks(null)
        } catch (_: Throwable) {
        }
    }

    private fun bindBestUnderlyingNetwork() {
        val preferred = underlyingNetwork ?: connectivityManager.allNetworks.firstOrNull { network ->
            val caps = connectivityManager.getNetworkCapabilities(network) ?: return@firstOrNull false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        if (preferred != null) {
            underlyingNetwork = preferred
            applyUnderlyingNetwork(preferred)
        }
    }

    private fun applyUnderlyingNetwork(network: Network) {
        try {
            setUnderlyingNetworks(arrayOf(network))
        } catch (_: Throwable) {
            // The app UID is excluded from the VPN as the primary loop guard.
            // An underlying-network hint failure must not kill a healthy core.
        }
    }

'''
    text = replace_once(
        text,
        "    private fun applyApplicationRouting(\n",
        methods + "    private fun applyApplicationRouting(\n",
        "underlying-network methods",
    )

    text = replace_once(
        text,
        "    private fun stopTunnel(stopService: Boolean) {\n"
        "        mainHandler.removeCallbacks(statsTick)\n",
        "    private fun stopTunnel(stopService: Boolean) {\n"
        "        mainHandler.removeCallbacks(statsTick)\n"
        "        stopUnderlyingNetworkMonitor()\n",
        "network monitor stop",
    )

    text = replace_once(
        text,
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n",
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n"
        "        stopUnderlyingNetworkMonitor()\n",
        "network monitor destroy cleanup",
    )

    SERVICE.write_text(text, encoding="utf-8")

    # Preserve the WireGuard regression fix in the same always-executed Android
    # hardening step so a regenerated MainActivity cannot reintroduce the
    # simultaneous-two-VpnService race.
    activity = MAIN.read_text(encoding="utf-8")
    old_handoff = '''        executor.execute {
            try {
                if (xrayActive) AeroXrayVpnService.stop(this)
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.UP, parsed)
'''
    new_handoff = '''        executor.execute {
            try {
                if (xrayActive || AeroXrayState.current().status != "disconnected") {
                    AeroXrayVpnService.stop(this)
                    val deadline = System.currentTimeMillis() + 3000L
                    while (AeroXrayState.current().status != "disconnected" &&
                        System.currentTimeMillis() < deadline) {
                        Thread.sleep(50L)
                    }
                    if (AeroXrayState.current().status != "disconnected") {
                        throw IllegalStateException("Xray VPN did not release Android TUN")
                    }
                }
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.UP, parsed)
'''
    activity = replace_once(activity, old_handoff, new_handoff, "Xray to WireGuard handoff")
    MAIN.write_text(activity, encoding="utf-8")

    service_check = SERVICE.read_text(encoding="utf-8")
    activity_check = MAIN.read_text(encoding="utf-8")
    required = [
        'controller.startLoop(runtimeConfig, established.fd)',
        'setUnderlyingNetworks(arrayOf(network))',
        'NET_CAPABILITY_NOT_VPN',
        '.put("name", "xray0")',
        '.put("userLevel", 8)',
        '.put("level", 8)',
        '.put("outboundTag", "proxy")',
        'measureDelay("https://cp.cloudflare.com/generate_204")',
        'startUnderlyingNetworkMonitor()',
    ]
    missing = [marker for marker in required if marker not in service_check]
    if missing:
        raise SystemExit(f"Android Xray datapath hardening incomplete: {missing}")

    forbidden = [
        'val coreDelayMs = controller.measureDelay(',
        '.addAddress("fd42:42:42::2", 126)',
        '.addRoute("::", 0)',
        '.put("name", "wesi0")',
        '.put("userLevel", 0)',
    ]
    survived = [marker for marker in forbidden if marker in service_check]
    if survived:
        raise SystemExit(f"Unsafe/legacy Android Xray datapath markers survived: {survived}")
    if 'Xray VPN did not release Android TUN' not in activity_check:
        raise SystemExit("Serialized Xray -> WireGuard handoff is missing")

    print(
        "Hardened Android Xray datapath: IPv4-only VPN, v2rayNG-compatible TUN policy, "
        "post-core network binding, non-fatal startup, serialized WireGuard handoff"
    )


if __name__ == "__main__":
    main()
