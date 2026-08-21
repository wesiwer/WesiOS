#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/AeroSingBoxVpnService.kt"


def main() -> None:
    text = SERVICE.read_text(encoding="utf-8")
    anchor = '''    ): String {
        val outbound = when (protocol) {
'''
    replacement = '''    ): String {
        if (rawConfig.trimStart().startsWith("{")) {
            val root = JSONObject(rawConfig)
            val inbounds = root.optJSONArray("inbounds")
                ?: throw IllegalArgumentException("sing-box profile has no inbounds")
            var tun: JSONObject? = null
            for (index in 0 until inbounds.length()) {
                val candidate = inbounds.optJSONObject(index) ?: continue
                if (candidate.optString("type") == "tun") {
                    tun = candidate
                    break
                }
            }
            val tunInbound = tun ?: throw IllegalArgumentException("sing-box profile has no TUN inbound")
            val cleanPackages = packages.filter { it.isNotBlank() && it != selfPackage }.distinct()
            tunInbound.remove("include_package")
            tunInbound.remove("exclude_package")
            when (splitMode) {
                "allowlist" -> {
                    if (cleanPackages.isEmpty()) throw IllegalArgumentException("Select at least one application")
                    tunInbound.put("include_package", JSONArray(cleanPackages))
                }
                "denylist" -> tunInbound.put(
                    "exclude_package",
                    JSONArray(listOf(selfPackage) + cleanPackages),
                )
                "allTraffic" -> tunInbound.put("exclude_package", JSONArray().put(selfPackage))
                else -> throw IllegalArgumentException("Unknown split-routing mode")
            }
            return root.toString()
        }

        val outbound = when (protocol) {
'''
    if replacement not in text:
        if text.count(anchor) != 1:
            raise SystemExit(f"sing-box JSON profile patch expected one anchor, found {text.count(anchor)}")
        text = text.replace(anchor, replacement, 1)
    SERVICE.write_text(text, encoding="utf-8")
    if 'rawConfig.trimStart().startsWith("{")' not in text:
        raise SystemExit("server-built sing-box JSON support is missing")
    print("Enabled server-built sing-box JSON profiles with client-side app routing")


if __name__ == "__main__":
    main()
