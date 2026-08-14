#!/usr/bin/env python3
"""Publish one prepared Wesi AI media-engine ZIP into Wesi artifact storage.

This script never downloads or builds third-party models. It only takes a
package that was already reviewed/tested, computes immutable metadata, copies
it into the artifact tree and atomically updates media-engines/manifest.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import tempfile

KINDS = {"image", "music", "video"}
PLATFORMS = {"windows", "linux", "macos", "android", "ios"}


def positive_int(raw: str) -> int:
    value = int(raw)
    if value < 0:
        raise argparse.ArgumentTypeError("must be >= 0")
    return value


def safe_relative(raw: str) -> str:
    value = raw.strip().replace("\\", "/")
    path = pathlib.PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts:
        raise argparse.ArgumentTypeError("must be a safe relative path")
    return value


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", required=True, choices=sorted(KINDS))
    parser.add_argument("--id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--archive", required=True, type=pathlib.Path)
    parser.add_argument("--license", required=True)
    parser.add_argument("--license-url", required=True)
    parser.add_argument("--launcher", required=True, type=safe_relative)
    parser.add_argument("--min-ram-gb", default=0, type=positive_int)
    parser.add_argument("--recommended-vram-gb", default=0, type=positive_int)
    parser.add_argument("--platform", action="append", choices=sorted(PLATFORMS), required=True)
    parser.add_argument("--disabled", action="store_true")
    parser.add_argument(
        "--artifacts-dir",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("WESI_ARTIFACTS_DIR", "/srv/wesi-artifacts")),
    )
    return parser.parse_args()


def validate_token(name: str, value: str) -> str:
    clean = value.strip()
    if not clean or len(clean) > 120 or any(c in clean for c in "/\\\n\r\0"):
        raise SystemExit(f"invalid {name}")
    return clean


def main() -> None:
    args = parse_args()
    archive = args.archive.resolve()
    if not archive.is_file() or archive.suffix.lower() != ".zip":
        raise SystemExit("--archive must be an existing .zip file")

    package_id = validate_token("id", args.id)
    version = validate_token("version", args.version)
    root = args.artifacts_dir.resolve()
    catalog_dir = root / "media-engines"
    package_dir = catalog_dir / "packages" / args.kind / package_id / version
    package_dir.mkdir(parents=True, exist_ok=True)

    # Keep filename deterministic and independent from upload workstation.
    target_name = f"{package_id}-{version}.zip"
    target = package_dir / target_name
    tmp_target = package_dir / (target_name + ".uploading")
    shutil.copyfile(archive, tmp_target)
    os.replace(tmp_target, target)

    size = target.stat().st_size
    checksum = sha256_file(target)
    relative_path = target.relative_to(root).as_posix()

    manifest_path = catalog_dir / "manifest.json"
    current = {"schema": 1, "engines": []}
    if manifest_path.exists():
        with manifest_path.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if loaded.get("schema") != 1 or not isinstance(loaded.get("engines"), list):
            raise SystemExit("existing manifest has an unsupported schema")
        current = loaded

    entry = {
        "kind": args.kind,
        "id": package_id,
        "name": args.name.strip(),
        "version": version,
        "path": relative_path,
        "sha256": checksum,
        "sizeBytes": size,
        "license": args.license.strip(),
        "licenseUrl": args.license_url.strip(),
        "launcher": args.launcher,
        "platforms": sorted(set(args.platform)),
        "requirements": {
            "minRamGb": args.min_ram_gb,
            "recommendedVramGb": args.recommended_vram_gb,
        },
        "enabled": not args.disabled,
    }

    engines = [
        item
        for item in current["engines"]
        if not (isinstance(item, dict) and item.get("kind") == args.kind)
    ]
    engines.append(entry)
    engines.sort(key=lambda item: str(item.get("kind", "")))
    next_manifest = {"schema": 1, "engines": engines}

    catalog_dir.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix="manifest.", suffix=".json", dir=catalog_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(next_manifest, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_name, 0o644)
        os.replace(temp_name, manifest_path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)

    print(json.dumps({
        "ok": True,
        "kind": args.kind,
        "path": relative_path,
        "sizeBytes": size,
        "sha256": checksum,
        "manifest": str(manifest_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
