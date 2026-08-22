#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
LOCK = json.loads((ROOT / "DEPENDENCIES.lock.json").read_text(encoding="utf-8"))


def require(path: Path, *markers: str) -> str:
    text = path.read_text(encoding="utf-8")
    missing = [marker for marker in markers if marker not in text]
    if missing:
        raise SystemExit(f"{path.relative_to(REPO)} missing security markers: {missing}")
    return text


def verify_dependency_sources() -> None:
    xray = LOCK["androidVpn"]["androidLibXrayLite"]
    require(
        ROOT / "scripts/download_xray_aar.py",
        f'XRAY_ANDROID_VERSION = "{xray["version"]}"',
        f'XRAY_ANDROID_COMMIT = "{xray["sourceCommit"]}"',
        f'XRAY_ANDROID_SHA256 = "{xray["sha256"]}"',
        "digest mismatch",
    )

    sing = LOCK["androidVpn"]["singBox"]
    require(
        ROOT / "scripts/build_android_singbox.py",
        f'SING_BOX_TAG = "{sing["version"]}"',
        f'SING_BOX_COMMIT = "{sing["sourceCommit"]}"',
        f'GOMOBILE_VERSION = "{sing["gomobile"]}"',
        "actual_commit != SING_BOX_COMMIT",
    )

    hev = LOCK["androidVpn"]["hevSocks5Tunnel"]
    require(
        ROOT / "scripts/configure_android_hev_tun.py",
        f'HEV_COMMIT = "{hev["sourceCommit"]}"',
    )

    awg = LOCK["androidVpn"]["amneziaWgAndroid"]
    require(
        ROOT / "scripts/enable_android_amneziawg_backend.py",
        f'AMNEZIAWG_VERSION = "{awg["mavenVersion"]}"',
    )


def verify_release_workflows() -> None:
    actions = LOCK["githubActions"]
    workflows = [
        REPO / ".github/workflows/wesi-aero-arm64.yml",
        REPO / ".github/workflows/wesi-aero-android-live.yml",
        REPO / ".github/workflows/wesi-aero-xray-baseline.yml",
        REPO / ".github/workflows/wesi-aero-expand-protocols.yml",
    ]
    approved = {
        f"actions/checkout@{actions['actions/checkout']}",
        f"actions/setup-java@{actions['actions/setup-java']}",
        f"actions/setup-go@{actions['actions/setup-go']}",
        f"actions/cache@{actions['actions/cache']}",
        f"actions/upload-artifact@{actions['actions/upload-artifact']}",
        f"subosito/flutter-action@{actions['subosito/flutter-action']}",
    }
    uses_pattern = re.compile(r"(?m)^\s*(?:-\s*)?uses:\s*([^\s#]+)")
    floating_pattern = re.compile(
        r"(?m)^\s*(?:-\s*)?uses:\s*[^\s#]+@(v\d*|main|master|stable)(?:\s|$)"
    )
    for path in workflows:
        text = path.read_text(encoding="utf-8")
        for use in uses_pattern.findall(text):
            if use not in approved:
                raise SystemExit(f"Unapproved/unpinned action in {path.name}: {use}")
        if floating_pattern.search(text):
            raise SystemExit(f"Floating GitHub Action ref in {path.name}")

    for path in workflows[:2]:
        require(path, "flutter-version: '3.47.1'", "go-version: '1.24.13'")


def verify_server_fail_closed() -> None:
    provisioner = require(
        ROOT / "server-node/src/provisioner.mjs",
        "function profileProtocolCandidates(protocol)",
        "return [protocol]",
        "Profile protocol mismatch",
    )
    if "['wireguard', 'amneziawg']" in provisioner:
        raise SystemExit("WireGuard profile lookup still aliases AmneziaWG")
    if "migrationCompatible" in provisioner:
        raise SystemExit("Legacy WireGuard/AmneziaWG protocol substitution remains enabled")

    config = require(
        ROOT / "server-node/src/config.mjs",
        "WESI_AERO_MASTER_KEY with at least 32 characters is required",
        "environment.WESI_AERO_TECHNICAL_LOGS === 'true'",
        "environment.WESI_AERO_ALLOW_MOCK_PAYMENTS === 'true'",
    )
    if "technicalLogs: environment.WESI_AERO_TECHNICAL_LOGS !== 'false'" in config:
        raise SystemExit("Technical logging is fail-open")

    require(
        ROOT / "server-node/scripts/setup-control-plane-prototype.sh",
        "UMask=0077",
        "NoNewPrivileges=true",
        "ProtectSystem=strict",
        "ProtectKernelTunables=true",
        "ProtectKernelModules=true",
        "ProtectControlGroups=true",
        "RestrictNamespaces=true",
        "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6",
    )

    nginx = require(
        ROOT / "server-node/scripts/configure-control-plane-https.sh",
        "access_log off",
        "include $TRANSPORT_SNIPPET;",
        'TRANSPORT_SNIPPET="/etc/nginx/snippets/wesi-aero-transports.conf"',
    )
    if "X-Forwarded-For $proxy_add_x_forwarded_for" in nginx or "X-Real-IP $remote_addr" in nginx:
        raise SystemExit("Public control plane still forwards client IP metadata to Node")


def verify_restrictive_network_layer() -> None:
    transport = require(
        ROOT / "server-node/scripts/setup-restrictive-transports.sh",
        'listen:"127.0.0.1"',
        'type:"ws"',
        'type:"grpc"',
        'type:"http"',
        'port:"443"',
        'sni:$host',
        "No third-party SNI/domain fronting",
        'proxy_set_header X-Real-IP "";',
        'proxy_set_header X-Forwarded-For "";',
        "sing-box check -c \"$tmp_config\"",
        "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK",
    )
    if 'listen:"0.0.0.0"' in transport or 'listen:"::"' in transport:
        raise SystemExit("Restrictive transport backend is not loopback-only")
    if "proxy_add_x_forwarded_for" in transport:
        raise SystemExit("Restrictive transport forwards source-IP metadata")

    sync = require(
        ROOT / "server-node/scripts/sync-live-protocols.sh",
        'publicPort:443',
        'primary:{protocol:"vmess",transport:"websocket"}',
        'candidates:["websocket","grpc","http2"]',
        'domainFronting:false',
        'thirdPartyCdn:false',
        'edgePolicy:"wesi-owned-or-explicitly-authorized"',
    )
    if "domainFronting:true" in sync or "thirdPartyCdn:true" in sync:
        raise SystemExit("Restrictive-network catalog enables unauthorized fronting/CDN routing")

    deploy = require(
        REPO / ".github/workflows/wesi-aero-expand-protocols.yml",
        "setup-restrictive-transports.sh",
        "wesi-aero-restrictive-transports.service",
        "socks5h://127.0.0.1:19080",
        "https://example.com/",
        "127\\.0\\.0\\.1:/",
        'domainFronting == false',
    )
    if "curl -k" in deploy or "insecure:true" in deploy:
        raise SystemExit("Restrictive-network E2E verification disables TLS verification")


def verify_rust_core() -> None:
    rust = LOCK["toolchains"]["rust"]
    require(
        ROOT / "core/wesi-tunnel-core/rust-toolchain.toml",
        f'channel = "{rust}"',
    )
    core = require(
        ROOT / "core/wesi-tunnel-core/src/lib.rs",
        "#![forbid(unsafe_code)]",
        "stale async callbacks",
        "Action::BlockTraffic",
        "TunnelState::Verifying",
        "Transport::TlsWebSocket443",
        "Transport::TlsGrpc443",
        "Transport::TlsHttp2On443",
        "Topology::TrustedEdgeExit",
        "MasqueH3On443",
        "restrictive_tcp_443_routes",
    )
    live_policy = core.split("pub fn restrictive_tcp_443_routes", 1)[1].split(
        "pub const fn restrictive_http2_candidate", 1
    )[0]
    if "MasqueH3On443" in live_policy:
        raise SystemExit("MASQUE/HTTP3 is advertised in the live restrictive fallback before verification")


def main() -> None:
    verify_dependency_sources()
    verify_release_workflows()
    verify_server_fail_closed()
    verify_restrictive_network_layer()
    verify_rust_core()
    print("Wesi Aero security/build invariants verified")


if __name__ == "__main__":
    main()
