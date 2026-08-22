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
SING_BOX_COMMIT = "45ca32dcb966f07f97fc888fe8586e359dbe8405"
GOMOBILE_VERSION = "v0.1.12"
EXPECTED_GO_PREFIX = "go1.24."
REQUIRED_NDK = "28.0.13004108"


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, cwd=cwd, env=env, check=True)


def output(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def ensure_android_ndk(env: dict[str, str]) -> Path:
    sdk_raw = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if not sdk_raw:
        raise SystemExit("ANDROID_HOME/ANDROID_SDK_ROOT is required to build sing-box")
    sdk = Path(sdk_raw)
    target = sdk / "ndk" / REQUIRED_NDK
    if not (target / "toolchains/llvm/prebuilt").is_dir():
        sdkmanager = shutil.which("sdkmanager")
        if not sdkmanager:
            candidates = [
                sdk / "cmdline-tools/latest/bin/sdkmanager",
                *sorted((sdk / "cmdline-tools").glob("*/bin/sdkmanager"), reverse=True),
                sdk / "tools/bin/sdkmanager",
            ]
            sdkmanager = next((str(p) for p in candidates if p.is_file()), None)
        if not sdkmanager:
            raise SystemExit("Android sdkmanager was not found")
        subprocess.run(
            [sdkmanager, f"ndk;{REQUIRED_NDK}"],
            input="y\n" * 20,
            text=True,
            env=env,
            check=True,
        )
    if not target.is_dir():
        raise SystemExit(f"Android NDK {REQUIRED_NDK} was not installed")
    env["ANDROID_NDK_HOME"] = str(target)
    env["ANDROID_NDK_ROOT"] = str(target)
    env["NDK_HOME"] = str(target)
    print(f"Using Android NDK {REQUIRED_NDK}: {target}")
    return target


def bootstrap_gomobile(env: dict[str, str]) -> None:
    gopath = Path(output("go", "env", "GOPATH"))
    gobin = gopath / "bin"
    gomobile = gobin / "gomobile"
    gobind = gobin / "gobind"
    if not gomobile.is_file() or not gobind.is_file():
        run(
            "go",
            "install",
            f"github.com/sagernet/gomobile/cmd/gomobile@{GOMOBILE_VERSION}",
            env=env,
        )
        run(
            "go",
            "install",
            f"github.com/sagernet/gomobile/cmd/gobind@{GOMOBILE_VERSION}",
            env=env,
        )
    env["PATH"] = f"{gobin}:{env.get('PATH', '')}"
    run(str(gomobile), "init", env=env)


def disable_unused_naive_outbound(source: Path) -> None:
    # The stock Android builder enables NaiveProxy in sharedTags. Wesi Aero
    # does not expose that outbound, so remove only the build tag from the main
    # Android variant. The remaining string in filterTags(...,
    # "with_naive_outbound") belongs to sing-box's legacy variant and is not an
    # enabled feature by itself.
    builder = source / "cmd/internal/build_libbox/main.go"
    text = builder.read_text(encoding="utf-8")
    shared_anchor = 'sharedTags = append(sharedTags, "with_gvisor", "with_quic", "with_wireguard", "with_utls", "with_naive_outbound",'
    shared_replacement = 'sharedTags = append(sharedTags, "with_gvisor", "with_quic", "with_wireguard", "with_utls",'
    if shared_anchor not in text:
        raise SystemExit("sing-box builder layout changed: shared NaiveProxy tag not found")
    text = text.replace(shared_anchor, shared_replacement, 1)
    builder.write_text(text, encoding="utf-8")
    shared_line = next(
        (line for line in text.splitlines() if line.strip().startswith("sharedTags = append(sharedTags")),
        "",
    )
    if '"with_naive_outbound"' in shared_line:
        raise SystemExit("failed to disable NaiveProxy in sing-box shared Android tags")
    print("Disabled unused sing-box NaiveProxy/Cronet feature")


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

    env = os.environ.copy()
    env.setdefault("GOTOOLCHAIN", "auto")
    ensure_android_ndk(env)
    bootstrap_gomobile(env)

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
            env=env,
        )
        actual_commit = output("git", "rev-parse", "HEAD", cwd=source)
        if actual_commit != SING_BOX_COMMIT:
            raise SystemExit(
                "sing-box tag does not resolve to the approved source commit: "
                f"expected {SING_BOX_COMMIT}, got {actual_commit}"
            )
        disable_unused_naive_outbound(source)
        bind_target = os.environ.get("WESI_AERO_SINGBOX_TARGET", "android/arm64")
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
        f"Built sing-box {SING_BOX_TAG}@{SING_BOX_COMMIT[:12]} libbox Android core: "
        f"{OUTPUT} ({OUTPUT.stat().st_size} bytes)"
    )


if __name__ == "__main__":
    main()
