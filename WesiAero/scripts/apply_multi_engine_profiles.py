#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "lib/src/models/gateway_models.dart"
ENGINE = ROOT / "lib/src/services/gateway_engine.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_models() -> None:
    text = MODELS.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  const ImportedGatewayConfig({\n"
        "    required this.protocol,\n"
        "    required this.displayName,\n"
        "    required this.rawValue,\n"
        "  });\n\n"
        "  final GatewayProtocol protocol;\n"
        "  final String displayName;\n"
        "  final String rawValue;\n",
        "  const ImportedGatewayConfig({\n"
        "    required this.protocol,\n"
        "    required this.displayName,\n"
        "    required this.rawValue,\n"
        "    this.engineHint,\n"
        "  });\n\n"
        "  final GatewayProtocol protocol;\n"
        "  final String displayName;\n"
        "  final String rawValue;\n"
        "  final TunnelEngine? engineHint;\n",
        "ImportedGatewayConfig engine hint",
    )
    MODELS.write_text(text, encoding="utf-8")


def patch_engine() -> None:
    text = ENGINE.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "    await _provisionProfile(node: node, protocol: resolvedProtocol);",
        "    await _provisionProfile(\n"
        "      node: node,\n"
        "      protocol: resolvedProtocol,\n"
        "      engine: resolvedEngine,\n"
        "    );",
        "provision selected engine",
    )
    text = replace_once(
        text,
        "  Future<void> _provisionProfile({\n"
        "    required GatewayNode node,\n"
        "    required GatewayProtocol protocol,\n"
        "  }) async {",
        "  Future<void> _provisionProfile({\n"
        "    required GatewayNode node,\n"
        "    required GatewayProtocol protocol,\n"
        "    required TunnelEngine engine,\n"
        "  }) async {",
        "provision signature",
    )
    old = """    final rawConfig = profile['clientConfig'];
    if (rawConfig is! String || rawConfig.trim().isEmpty) {
      throw const AeroApiException(
        'PROFILE_NOT_PROVISIONED',
        'Сервер вернул пустой профиль подключения.',
      );
    }

    final parsed = GatewayConfigParser.parse(rawConfig);
    if (parsed.protocol != protocol) {
      throw const AeroApiException(
        'PROFILE_PROTOCOL_MISMATCH',
        'Протокол серверного профиля не совпадает с выбранным.',
      );
    }
    await importConfig(parsed);
    await _secretStore.saveProfile(parsed);
"""
    new = """    final rawConfig = profile['clientConfig'];
    if (rawConfig is! String || rawConfig.trim().isEmpty) {
      throw const AeroApiException(
        'PROFILE_NOT_PROVISIONED',
        'Сервер вернул пустой профиль подключения.',
      );
    }

    final ImportedGatewayConfig parsed;
    if (engine == TunnelEngine.singBox) {
      final singBoxConfig = profile['singBoxConfig'];
      if (singBoxConfig is! String || singBoxConfig.trim().isEmpty) {
        throw const AeroApiException(
          'ENGINE_PROFILE_UNAVAILABLE',
          'Сервер не выдал профиль для sing-box.',
        );
      }
      parsed = ImportedGatewayConfig(
        protocol: protocol,
        displayName: '${protocol.title} · sing-box',
        rawValue: singBoxConfig,
        engineHint: TunnelEngine.singBox,
      );
    } else {
      final decoded = GatewayConfigParser.parse(rawConfig);
      if (decoded.protocol != protocol) {
        throw const AeroApiException(
          'PROFILE_PROTOCOL_MISMATCH',
          'Протокол серверного профиля не совпадает с выбранным.',
        );
      }
      parsed = ImportedGatewayConfig(
        protocol: decoded.protocol,
        displayName: decoded.displayName,
        rawValue: decoded.rawValue,
        engineHint: engine,
      );
    }
    await importConfig(parsed);
    await _secretStore.saveProfile(parsed);
"""
    text = replace_once(text, old, new, "engine-specific profile selection")
    text = replace_once(
        text,
        "      'protocol': config.protocol.wireName,\n"
        "      'displayName': config.displayName,\n"
        "      'config': config.rawValue,",
        "      'protocol': config.protocol.wireName,\n"
        "      'engine': config.engineHint?.wireName ?? 'auto',\n"
        "      'displayName': config.displayName,\n"
        "      'config': config.rawValue,",
        "native import engine",
    )

    # Automatic mode is deliberately 443-first. The live VMess lease is not a
    # raw 8444 profile anymore: the control plane converts it to the Wesi-owned
    # TLS/443 restrictive profile and sing-box. Explicit user protocol choices
    # remain untouched.
    text = replace_once(
        text,
        "    const priority = [\n"
        "      GatewayProtocol.vlessReality,\n"
        "      GatewayProtocol.hysteria2,\n"
        "      GatewayProtocol.tuic,\n"
        "      GatewayProtocol.vmess,\n"
        "      GatewayProtocol.trojan,\n"
        "      GatewayProtocol.shadowsocks,\n"
        "      GatewayProtocol.amneziaWg,\n"
        "      GatewayProtocol.wireGuard,\n"
        "    ];",
        "    const priority = [\n"
        "      GatewayProtocol.vmess,\n"
        "      GatewayProtocol.vlessReality,\n"
        "      GatewayProtocol.trojan,\n"
        "      GatewayProtocol.shadowsocks,\n"
        "      GatewayProtocol.hysteria2,\n"
        "      GatewayProtocol.tuic,\n"
        "      GatewayProtocol.amneziaWg,\n"
        "      GatewayProtocol.wireGuard,\n"
        "    ];",
        "443-first automatic protocol priority",
    )
    ENGINE.write_text(text, encoding="utf-8")


def main() -> None:
    patch_models()
    patch_engine()
    print('Applied engine-aware profiles and HTTPS/443-first automatic routing')


if __name__ == '__main__':
    main()
