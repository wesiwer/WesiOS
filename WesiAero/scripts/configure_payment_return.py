#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from configure_android_wireguard import patch_gradle, write_activity


def configure_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
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

    # The CI/bootstrap path already calls this script after `flutter create`.
    # Configure the real native WireGuard backend in the same deterministic step.
    patch_gradle()
    write_activity()
