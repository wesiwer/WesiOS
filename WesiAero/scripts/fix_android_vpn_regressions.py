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


def main() -> None:
    if not SERVICE.exists() or not MAIN.exists():
        raise SystemExit("Generate Android VPN integrations before applying regression fixes")

    service = SERVICE.read_text(encoding="utf-8")
    fatal_probe = '''            val coreDelayMs = controller.measureDelay("https://cp.cloudflare.com/generate_204")
            if (coreDelayMs < 0) {
                throw IllegalStateException("Xray outbound health check failed")
            }
'''
    if fatal_probe in service:
        service = service.replace(fatal_probe, "", 1)
    if 'measureDelay("https://cp.cloudflare.com/generate_204")' in service:
        raise SystemExit("Fatal Cloudflare Xray startup probe is still present")
    SERVICE.write_text(service, encoding="utf-8")

    activity = MAIN.read_text(encoding="utf-8")
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
    activity = replace_once(activity, old_handoff, new_handoff, "Xray to WireGuard handoff")
    MAIN.write_text(activity, encoding="utf-8")

    service_check = SERVICE.read_text(encoding="utf-8")
    activity_check = MAIN.read_text(encoding="utf-8")
    required = [
        'controller.startLoop(runtimeConfig, established.fd)',
        '.put("outboundTag", "proxy")',
    ]
    missing = [marker for marker in required if marker not in service_check]
    if missing:
        raise SystemExit(f"Xray datapath markers missing after regression fix: {missing}")
    if 'measureDelay("https://cp.cloudflare.com/generate_204")' in service_check:
        raise SystemExit("Cloudflare startup probe unexpectedly survived")
    if 'Xray VPN did not release Android TUN' not in activity_check:
        raise SystemExit("Serialized Xray -> WireGuard handoff is missing")

    print("Fixed Android VPN regressions: non-fatal Xray startup + serialized Xray/WireGuard TUN handoff")


if __name__ == "__main__":
    main()
