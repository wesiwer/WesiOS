#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from configure_android_wireguard import main as configure_wireguard


def configure_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    internet_permission = (
        '    <uses-permission android:name="android.permission.INTERNET" />\n'
    )
    if 'android.permission.INTERNET' not in text:
        manifest_tag_end = text.find('>')
        if manifest_tag_end < 0:
            raise SystemExit(f"Invalid Android manifest: {path}")
        text = (
            text[: manifest_tag_end + 1]
            + '\n'
            + internet_permission
            + text[manifest_tag_end + 1 :]
        )

    if 'android:scheme="wesi-aero"' not in text:
        activity_end = "        </activity>"
        if activity_end not in text:
            raise SystemExit(f"Main activity closing tag not found in {path}")

        payment_return = """            <meta-data
                android:name="flutter_deeplinking_enabled"
                android:value="false" />
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="wesi-aero"
                    android:host="payment-return" />
            </intent-filter>
"""
        text = text.replace(activity_end, payment_return + activity_end, 1)

    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "android/app/src/main/AndroidManifest.xml"
    )
    if not manifest.is_file():
        raise SystemExit(f"Android manifest not found: {manifest}")

    configure_manifest(manifest)

    # CI and local platform bootstrap already invoke this script immediately
    # after `flutter create`. Keep the real native VPN backend in the exact same
    # deterministic step so no release APK can accidentally ship the preview
    # MethodChannel implementation.
    configure_wireguard()

    manifest_text = manifest.read_text(encoding="utf-8")
    gradle = Path("android/app/build.gradle.kts").read_text(encoding="utf-8")
    activity = Path(
        "android/app/src/main/kotlin/com/wesi/wesi_aero/MainActivity.kt"
    ).read_text(encoding="utf-8")
    if "android.permission.INTERNET" not in manifest_text:
        raise SystemExit("Android release manifest has no INTERNET permission")
    if "com.wireguard.android:tunnel:" not in gradle:
        raise SystemExit("WireGuard Android dependency was not configured")
    if "GoBackend" not in activity or "VpnService.prepare" not in activity:
        raise SystemExit("Native Android VPN bridge was not configured")
    print("Configured Wesi Aero Android VPN bridge and payment return")
