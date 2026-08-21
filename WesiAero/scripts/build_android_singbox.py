#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "android/app/libs/libbox.aar"
SING_BOX_REPO = "https://github.com/SagerNet/sing-box.git"
SING_BOX_TAG = "v1.13.18"
EXPECTED_GO_PREFIX = "go1.24."


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, cwd=cwd, env=env, check=True)


def output(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def main() -> None:
    go_version = output("go", "version")
    if EXPECTED_GO_PREFIX not in go_version:
        raise SystemExit(
            f"sing-box {SING_BOX_TAG} requires Go 1.24.x; got {go_version}"
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.is_file() and OUTPUT.stat().st_size > 5_000_000:
        print(f"Using cached {OUTPUT} ({OUTPUT.stat().st_size} bytes)")
        return

    with tempfile.TemporaryDirectory(prefix="wesi-singbox-") as temp_raw:
        source = Path(temp_raw) / "sing-box"
        run(
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            SING_BOX_TAG,
            SING_BOX_REPO,
            str(source),
        )
        bind_target = os.environ.get("WESI_AERO_SINGBOX_TARGET", "android/arm64")
        env = os.environ.copy()
        env.setdefault("GOTOOLCHAIN", "auto")
        run(
            "go",
            "run",
            "./cmd/internal/build_libbox",
            "-target",
            "android",
            "-platform",
            bind_target,
            cwd=source,
            env=env,
        )
        aar = source / "libbox.aar"
        if not aar.is_file() or aar.stat().st_size < 5_000_000:
            raise SystemExit("sing-box libbox.aar build did not produce a valid AAR")
        shutil.copy2(aar, OUTPUT)

    print(
        f"Built sing-box {SING_BOX_TAG} libbox Android core: "
        f"{OUTPUT} ({OUTPUT.stat().st_size} bytes)"
    )


if __name__ == "__main__":
    main()
