#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroXrayVpnService.kt"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one patch anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


def main() -> None:
    if not SERVICE.exists():
        raise SystemExit(f"Generate Android Xray integration first: {SERVICE} is missing")

    text = SERVICE.read_text(encoding="utf-8")

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

    text = replace_once(
        text,
        "        Seq.setContext(applicationContext)\n"
        "        Libv2ray.initCoreEnv(filesDir.absolutePath, \"\")\n",
        "        Seq.setContext(applicationContext)\n"
        "        Libv2ray.initCoreEnv(filesDir.absolutePath, \"\")\n"
        "        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager\n"
        "        startUnderlyingNetworkMonitor()\n",
        "service onCreate network monitor",
    )

    text = replace_once(
        text,
        "            val established = builder.establish()\n"
        "                ?: throw IllegalStateException(\"Android failed to create the VPN TUN interface\")\n"
        "            tun = established\n\n"
        "            val controller = Libv2ray.newCoreController(CoreCallback())\n",
        "            val established = builder.establish()\n"
        "                ?: throw IllegalStateException(\"Android failed to create the VPN TUN interface\")\n"
        "            tun = established\n"
        "            bindBestUnderlyingNetwork()\n\n"
        "            val controller = Libv2ray.newCoreController(CoreCallback())\n",
        "bind physical network after establish",
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
        "            val coreDelayMs = controller.measureDelay(\"https://cp.cloudflare.com/generate_204\")\n"
        "            if (coreDelayMs < 0) {\n"
        "                throw IllegalStateException(\"Xray outbound health check failed\")\n"
        "            }\n\n"
        "            connectedAtMs = System.currentTimeMillis()\n",
        "Xray outbound health probe",
    )

    # Built-in TUN has multiple outbounds. Make the intended data path explicit
    # instead of relying on Xray's first-outbound fallback semantics.
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
            // The self UID is excluded from the VPN as an additional loop guard;
            // failing to update the hint must not crash an already established TUN.
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
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n",
        "    override fun onDestroy() {\n"
        "        mainHandler.removeCallbacks(statsTick)\n"
        "        stopUnderlyingNetworkMonitor()\n",
        "network monitor cleanup",
    )

    SERVICE.write_text(text, encoding="utf-8")

    required = [
        "setUnderlyingNetworks(arrayOf(network))",
        "NET_CAPABILITY_NOT_VPN",
        "controller.measureDelay(\"https://cp.cloudflare.com/generate_204\")",
        '.put("inboundTag", JSONArray().put("tun"))',
        '.put("outboundTag", "proxy")',
    ]
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"Android Xray datapath hardening incomplete: {missing}")
    print("Hardened Android Xray TUN datapath: physical-network binding + explicit proxy route + health probe")


if __name__ == "__main__":
    main()
