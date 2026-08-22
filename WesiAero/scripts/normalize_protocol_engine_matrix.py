#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "lib/src/models/gateway_models.dart"


def main() -> None:
    text = MODELS.read_text(encoding="utf-8")
    old = '''  Set<TunnelEngine> get supportedEngines => switch (this) {
    GatewayProtocol.automatic => TunnelEngine.values.toSet(),
    GatewayProtocol.vlessReality ||
    GatewayProtocol.vmess ||
    GatewayProtocol.trojan ||
    GatewayProtocol.shadowsocks => const {
        TunnelEngine.automatic,
        TunnelEngine.singBox,
        TunnelEngine.xray,
      },
    GatewayProtocol.hysteria2 || GatewayProtocol.tuic => const {
        TunnelEngine.automatic,
        TunnelEngine.singBox,
      },
    GatewayProtocol.wireGuard => const {
        TunnelEngine.automatic,
        TunnelEngine.native,
        TunnelEngine.singBox,
      },
    GatewayProtocol.amneziaWg => const {
        TunnelEngine.automatic,
        TunnelEngine.native,
      },
  };
'''
    new = '''  Set<TunnelEngine> get supportedEngines => switch (this) {
    GatewayProtocol.automatic => TunnelEngine.values.toSet(),
    GatewayProtocol.vlessReality || GatewayProtocol.vmess => const {
        TunnelEngine.automatic,
        TunnelEngine.singBox,
        TunnelEngine.xray,
      },
    GatewayProtocol.trojan ||
    GatewayProtocol.shadowsocks ||
    GatewayProtocol.hysteria2 ||
    GatewayProtocol.tuic => const {
        TunnelEngine.automatic,
        TunnelEngine.singBox,
      },
    GatewayProtocol.wireGuard => const {
        TunnelEngine.automatic,
        TunnelEngine.native,
      },
    GatewayProtocol.amneziaWg => const {
        TunnelEngine.automatic,
        TunnelEngine.native,
      },
  };
'''
    if new not in text:
        if text.count(old) != 1:
            raise SystemExit("GatewayProtocol.supportedEngines anchor mismatch")
        text = text.replace(old, new, 1)
    MODELS.write_text(text, encoding="utf-8")
    print("Aligned protocol/engine matrix with installed Android backends")


if __name__ == "__main__":
    main()
