#!/usr/bin/env python3
from __future__ import annotations

import shutil
import urllib.request
from pathlib import Path

XRAY_ANDROID_VERSION = "v26.5.19"
XRAY_ANDROID_URL = (
    "https://github.com/2dust/AndroidLibXrayLite/releases/download/"
    f"{XRAY_ANDROID_VERSION}/libv2ray.aar"
)
ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "android/app/libs/libv2ray.aar"


def main() -> None:
    if DESTINATION.is_file() and DESTINATION.stat().st_size > 1_000_000:
        print(f"Using cached {DESTINATION}")
        return

    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    temporary = DESTINATION.with_suffix(".aar.part")
    request = urllib.request.Request(
        XRAY_ANDROID_URL,
        headers={"User-Agent": "Wesi-Aero-CI/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if temporary.stat().st_size <= 1_000_000:
            raise SystemExit("Downloaded Xray AAR is unexpectedly small")
        temporary.replace(DESTINATION)
    finally:
        temporary.unlink(missing_ok=True)

    print(f"Downloaded AndroidLibXrayLite {XRAY_ANDROID_VERSION} to {DESTINATION}")


if __name__ == "__main__":
    main()
