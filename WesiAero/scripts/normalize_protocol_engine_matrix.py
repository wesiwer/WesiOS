#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "lib/src/models/gateway_models.dart"

START = '  Set<TunnelEngine> get supportedEngines => switch (this) {\n'
END = '  bool supportsEngine(TunnelEngine engine) =>\n'

MATRIX = '''  Set<TunnelEngine> get supportedEngines => switch (this) {
        GatewayProtocol.automatic => const {
            TunnelEngine.automatic,
            TunnelEngine.singBox,
            TunnelEngine.xray,
            TunnelEngine.native,
          },
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
        GatewayProtocol.wireGuard || GatewayProtocol.amneziaWg => const {
            TunnelEngine.automatic,
            TunnelEngine.native,
          },
      };

'''


def main() -> None:
    text = MODELS.read_text(encoding="utf-8")
    start = text.find(START)
    end = text.find(END, start + len(START)) if start >= 0 else -1
    if start < 0 or end < 0 or end <= start:
        raise SystemExit("GatewayProtocol.supportedEngines block was not found")

    text = text[:start] + MATRIX + text[end:]
    MODELS.write_text(text, encoding="utf-8")

    verified = MODELS.read_text(encoding="utf-8")
    required = [
        'GatewayProtocol.vlessReality || GatewayProtocol.vmess => const {',
        'GatewayProtocol.trojan ||',
        'GatewayProtocol.hysteria2 ||',
        'GatewayProtocol.wireGuard || GatewayProtocol.amneziaWg => const {',
    ]
    missing = [item for item in required if item not in verified]
    if missing:
        raise SystemExit(f"GatewayProtocol.supportedEngines verification failed: {missing}")

    # These combinations must not be exposed by the UI/runtime contract.
    block_start = verified.find(START)
    block_end = verified.find(END, block_start)
    block = verified[block_start:block_end]
    if 'GatewayProtocol.trojan ||\n        GatewayProtocol.shadowsocks => const {\n            TunnelEngine.automatic,\n            TunnelEngine.singBox,\n            TunnelEngine.xray' in block:
        raise SystemExit("Xray was accidentally exposed for Trojan/Shadowsocks")
    print("Aligned protocol/engine matrix with installed Android backends")


if __name__ == "__main__":
    main()
