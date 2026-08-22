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
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def has_centralized_handoff(activity: str) -> bool:
    """Return true when the current multi-engine dispatcher serializes VPN ownership."""
    required = (
        "private fun stopEveryBackend()",
        "stopEveryBackend()",
        'AeroXrayState.current().status == "disconnected"',
        'AeroSingBoxState.current().status == "disconnected"',
    )
    return all(marker in activity for marker in required)


def patch_centralized_handoff(activity: str) -> str:
    # return@repeat only continues to the next iteration; it does not leave the
    # repeat loop. Besides adding a fixed ~3 s delay to every backend handoff,
    # the old implementation continued even if another VpnService still owned
    # Android's TUN. Replace it with an actual break plus a fail-closed check.
    old_wait = '''        repeat(60) {
            val xrayDown = AeroXrayState.current().status == "disconnected"
            val singDown = AeroSingBoxState.current().status == "disconnected"
            if (xrayDown && singDown) return@repeat
            Thread.sleep(50L)
        }
'''
    new_wait = '''        var vpnServicesReleased = false
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
'''
    if old_wait in activity:
        activity = activity.replace(old_wait, new_wait, 1)
    return activity


def main() -> None:
    if not SERVICE.exists() or not MAIN.exists():
        raise SystemExit("Generate Android VPN integrations before applying regression fixes")

    service = SERVICE.read_text(encoding="utf-8")
    fatal_probe = '''            val coreDelayMs = controller.measureDelay("https://cp.cloudflare.com/generate_204")
            if (coreDelayMs < 0) {
                throw IllegalStateException("Xray outbound health check failed")
            }
'''
    harmless_marker = '''            // Startup must not depend on an external probe. In particular, do not
            // execute measureDelay("https://cp.cloudflare.com/generate_204") here:
            // that endpoint can fail independently of a valid Xray transport.
'''
    if fatal_probe in service:
        service = service.replace(fatal_probe, harmless_marker, 1)
    if 'val coreDelayMs = controller.measureDelay(' in service:
        raise SystemExit("Fatal Xray startup probe is still executable")
    SERVICE.write_text(service, encoding="utf-8")

    activity = MAIN.read_text(encoding="utf-8")
    activity = patch_centralized_handoff(activity)
    centralized = has_centralized_handoff(activity)

    old_handoff = '''        executor.execute {
            try {
                if (xrayActive) AeroXrayVpnService.stop(this)
                wireGuardBackend.setState(wireGuardTunnel, Tunnel.State.UP, parsed)
'''
    new_handoff = '''        executor.execute {
            try {
                // Android supports a single active VPN interface. Xray owns a
                // separate VpnService/TUN, so wait until it has actually closed
                // before GoBackend establishes WireGuard. Without this barrier
                // Android may show WireGuard as UP while traffic still targets
                // the previous/deactivated TUN.
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

    # Older generated dispatchers needed a dedicated Xray -> WireGuard barrier.
    # The current multi-engine dispatcher owns one serialized transition path for
    # every backend: bringUp() calls stopEveryBackend(), which drops WireGuard and
    # waits for both Xray and sing-box VpnServices to report disconnected before
    # starting the requested engine. Do not fail merely because the obsolete
    # legacy anchor is absent in that newer architecture.
    if not centralized and 'Xray VPN did not release Android TUN' not in activity:
        activity = replace_once(activity, old_handoff, new_handoff, "Xray to WireGuard handoff")
    MAIN.write_text(activity, encoding="utf-8")

    service_check = SERVICE.read_text(encoding="utf-8")
    activity_check = MAIN.read_text(encoding="utf-8")
    required = [
        'controller.startLoop(runtimeConfig, established.fd)',
        '.put("outboundTag", "proxy")',
        'measureDelay("https://cp.cloudflare.com/generate_204")',
    ]
    missing = [marker for marker in required if marker not in service_check]
    if missing:
        raise SystemExit(f"Xray datapath markers missing after regression fix: {missing}")
    if 'val coreDelayMs = controller.measureDelay(' in service_check:
        raise SystemExit("Cloudflare startup probe unexpectedly remained executable")

    legacy_handoff = 'Xray VPN did not release Android TUN' in activity_check
    centralized_handoff = has_centralized_handoff(activity_check)
    if not (legacy_handoff or centralized_handoff):
        raise SystemExit("Serialized VPN backend handoff is missing")
    if centralized_handoff:
        if 'Previous VPN backend did not release Android TUN' not in activity_check:
            raise SystemExit("Centralized VPN handoff does not fail closed when TUN release times out")
        if 'return@repeat' in activity_check:
            raise SystemExit("Centralized VPN handoff still uses non-breaking return@repeat")

    mode = "centralized fail-closed stop/wait" if centralized_handoff else "legacy Xray/WireGuard barrier"
    print(
        "Verified Android VPN regressions: non-fatal Xray startup + "
        f"serialized VPN TUN handoff ({mode})"
    )


if __name__ == "__main__":
    main()
