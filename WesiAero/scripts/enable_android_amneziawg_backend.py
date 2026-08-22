#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MAIN = ROOT / "android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt"
AMNEZIAWG_VERSION = "2.3.7"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_gradle() -> None:
    text = GRADLE.read_text(encoding="utf-8")
    # Standard WireGuard and AmneziaWG both ship a libwg-go.so. Shipping both
    # backends in one APK is ambiguous at runtime, so use the AWG-compatible
    # backend for both normal WireGuard and AmneziaWG profiles.
    lines = [
        line for line in text.splitlines()
        if "com.wireguard.android:tunnel:" not in line
    ]
    text = "\n".join(lines).rstrip() + "\n"
    marker = f'implementation("com.zaneschepke:amneziawg-android:{AMNEZIAWG_VERSION}")'
    if marker not in text:
        text = text.rstrip() + f'\n\ndependencies {{\n    {marker}\n}}\n'
    GRADLE.write_text(text, encoding="utf-8")


def patch_dispatcher() -> None:
    text = MAIN.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import com.wireguard.android.backend.GoBackend\n"
        "import com.wireguard.android.backend.Tunnel\n"
        "import com.wireguard.config.Config\n",
        "import org.amnezia.awg.backend.GoBackend\n"
        "import org.amnezia.awg.backend.Tunnel\n"
        "import org.amnezia.awg.config.Config\n",
        "AmneziaWG imports",
    )
    text = replace_once(
        text,
        '''                "native" -> {
                    if (requestedProtocol != "wireguard") {
                        throw IllegalArgumentException("Native backend is not ready for $requestedProtocol")
                    }
                    parseWireGuardConfig(value)
                }
''',
        '''                "native" -> {
                    if (requestedProtocol != "wireguard" && requestedProtocol != "amneziawg") {
                        throw IllegalArgumentException("Native backend is not ready for $requestedProtocol")
                    }
                    parseWireGuardConfig(value)
                }
''',
        "native profile validation",
    )
    text = replace_once(
        text,
        '''    private fun bringUpWireGuard(pending: PendingConnect) {
        if (pending.protocol != "wireguard") {
            throw IllegalStateException("Real AmneziaWG backend is not installed yet")
        }
''',
        '''    private fun bringUpWireGuard(pending: PendingConnect) {
        if (pending.protocol != "wireguard" && pending.protocol != "amneziawg") {
            throw IllegalStateException("Native WireGuard family backend cannot run ${pending.protocol}")
        }
''',
        "native tunnel protocol gate",
    )
    text = replace_once(
        text,
        '''            "wireguard" -> setOf("native")
            "amneziawg" -> emptySet()
''',
        '''            "wireguard", "amneziawg" -> setOf("native")
''',
        "runtime compatibility matrix",
    )
    text = replace_once(
        text,
        '''        "wireguard" -> "native"
        else -> "native"
''',
        '''        "wireguard", "amneziawg" -> "native"
        else -> "native"
''',
        "default native engine",
    )
    MAIN.write_text(text, encoding="utf-8")


def verify() -> None:
    gradle = GRADLE.read_text(encoding="utf-8")
    main = MAIN.read_text(encoding="utf-8")
    required = [
        f'com.zaneschepke:amneziawg-android:{AMNEZIAWG_VERSION}',
        'org.amnezia.awg.backend.GoBackend',
        'org.amnezia.awg.config.Config',
        '"wireguard", "amneziawg" -> setOf("native")',
    ]
    haystack = gradle + "\n" + main
    missing = [item for item in required if item not in haystack]
    if missing:
        raise SystemExit(f"AmneziaWG backend verification failed: {missing}")
    if "com.wireguard.android:tunnel:" in gradle:
        raise SystemExit("standard WireGuard Android backend still present; libwg-go collision risk")
    print(
        f"Enabled unified WireGuard/AmneziaWG Android backend ({AMNEZIAWG_VERSION}); "
        "one libwg-go implementation serves both profile families"
    )


def main() -> None:
    if not GRADLE.is_file() or not MAIN.is_file():
        raise SystemExit("Generate Android multi-engine dispatcher before enabling AmneziaWG")
    patch_gradle()
    patch_dispatcher()
    verify()


if __name__ == "__main__":
    main()
