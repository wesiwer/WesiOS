#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import shutil
import urllib.request
from pathlib import Path

XRAY_ANDROID_VERSION = "v26.5.19"
XRAY_ANDROID_COMMIT = "4c3a3cd051ac6a10d27ba1347a05fff2697ea272"
XRAY_ANDROID_SHA256 = "3d43b9344723e9c0625527de4f2bea0ee02c21180224e5ecab3384af143ca6d0"
XRAY_ANDROID_URL = (
    "https://github.com/2dust/AndroidLibXrayLite/releases/download/"
    f"{XRAY_ANDROID_VERSION}/libv2ray.aar"
)
ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "android/app/libs/libv2ray.aar"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path: Path) -> None:
    actual = sha256(path)
    if actual != XRAY_ANDROID_SHA256:
        raise SystemExit(
            "AndroidLibXrayLite digest mismatch: "
            f"expected {XRAY_ANDROID_SHA256}, got {actual}"
        )


def main() -> None:
    if DESTINATION.is_file() and DESTINATION.stat().st_size > 1_000_000:
        verify(DESTINATION)
        print(
            f"Using verified cached {DESTINATION} "
            f"({XRAY_ANDROID_VERSION}@{XRAY_ANDROID_COMMIT[:12]})"
        )
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
        verify(temporary)
        temporary.replace(DESTINATION)
    finally:
        temporary.unlink(missing_ok=True)

    print(
        f"Downloaded and verified AndroidLibXrayLite {XRAY_ANDROID_VERSION} "
        f"({XRAY_ANDROID_SHA256}) to {DESTINATION}"
    )


if __name__ == "__main__":
    main()
