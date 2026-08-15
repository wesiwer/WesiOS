from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"patch anchor missing in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


policy = ROOT / "lib/features/ai/runtime/wesi_local_runtime_policy.dart"
replace_once(
    policy,
    """    if (segments.any((segment) => segment == '..')) {\n      throw const WesiLocalRuntimePolicyException(\n        'WLR_PATH_ESCAPE',\n        'Выход за пределы workspace запрещён',\n      );\n    }\n\n    final candidate = p.normalize(p.absolute(p.join(root, relative)));\n""",
    """    if (segments.any((segment) => segment == '..')) {\n      throw const WesiLocalRuntimePolicyException(\n        'WLR_PATH_ESCAPE',\n        'Выход за пределы workspace запрещён',\n      );\n    }\n    final visibleSegments = segments\n        .where((segment) => segment.isNotEmpty && segment != '.')\n        .toList(growable: false);\n    if (visibleSegments.isNotEmpty &&\n        visibleSegments.first.toLowerCase() == '.wesi') {\n      throw const WesiLocalRuntimePolicyException(\n        'WLR_INTERNAL_PATH_FORBIDDEN',\n        'Внутреннее состояние local runtime недоступно AI-инструментам',\n      );\n    }\n\n    final candidate = p.normalize(p.absolute(p.join(root, relative)));\n""",
)
replace_once(policy, "    if (uri.hasUserInfo) {\n", "    if (uri.userInfo.isNotEmpty) {\n")
replace_once(
    policy,
    """    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {\n      final allZero = bytes.every((value) => value == 0);\n      if (allZero) return true;\n      final loopback = bytes.take(15).every((value) => value == 0) && bytes[15] == 1;\n      if (loopback) return true;\n      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local\n""",
    """    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {\n      final allZero = bytes.every((value) => value == 0);\n      if (allZero) return true;\n      final loopback =\n          bytes.take(15).every((value) => value == 0) && bytes[15] == 1;\n      if (loopback) return true;\n\n      // IPv4-mapped IPv6 must inherit IPv4 policy. Without this check an\n      // address such as ::ffff:127.0.0.1 could bypass the loopback guard.\n      final ipv4Mapped = bytes.take(10).every((value) => value == 0) &&\n          bytes[10] == 0xff &&\n          bytes[11] == 0xff;\n      if (ipv4Mapped) {\n        final a = bytes[12];\n        final b = bytes[13];\n        if (a == 0 || a == 10 || a == 127) return true;\n        if (a == 100 && b >= 64 && b <= 127) return true;\n        if (a == 169 && b == 254) return true;\n        if (a == 172 && b >= 16 && b <= 31) return true;\n        if (a == 192 && b == 168) return true;\n        if (a == 192 && (b == 0 || b == 2)) return true;\n        if (a == 198 && (b == 18 || b == 19 || b == 51)) return true;\n        if (a == 203 && b == 0 && bytes[14] == 113) return true;\n        if (a >= 224) return true;\n      }\n\n      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local\n""",
)

executor = ROOT / "lib/features/ai/runtime/wesi_local_runtime_executor.dart"
replace_once(
    executor,
    """    await for (final entity in Directory(path).list(followLinks: false)) {\n      if (entries.length >= context.limits.maxDirectoryEntries) {\n""",
    """    await for (final entity in Directory(path).list(followLinks: false)) {\n      // `.wesi` stores runtime HOME/tmp/hooks/audit and is deliberately not\n      // part of the model-visible workspace namespace.\n      if (p.equals(path, root) && p.basename(entity.path).toLowerCase() == '.wesi') {\n        continue;\n      }\n      if (entries.length >= context.limits.maxDirectoryEntries) {\n""",
)
replace_once(
    executor,
    """      if (!recursive && await Directory(path).list(followLinks: false).isNotEmpty) {\n""",
    """      if (!recursive &&\n          !(await Directory(path).list(followLinks: false).isEmpty)) {\n""",
)
replace_once(
    executor,
    """      final pinnedAddress = addresses.first;\n      final expectedHost = requestUri.host.toLowerCase();\n      final client = httpClientFactory()\n        ..findProxy = (_) => 'DIRECT'\n        ..connectionFactory = (url, proxyHost, proxyPort) {\n          if (proxyHost != null || proxyPort != null ||\n              url.host.toLowerCase() != expectedHost) {\n            throw const WesiLocalRuntimePolicyException(\n              'WLR_SSRF_BLOCKED',\n              'HTTP connection не соответствует проверенному назначению',\n            );\n          }\n          final port = url.hasPort\n              ? url.port\n              : (url.scheme.toLowerCase() == 'https' ? 443 : 80);\n          return Socket.startConnect(pinnedAddress, port);\n        };\n""",
    """      final pinnedAddress = addresses.first;\n      final expectedScheme = requestUri.scheme.toLowerCase();\n      final expectedHost = requestUri.host.toLowerCase();\n      final expectedPort = requestUri.hasPort\n          ? requestUri.port\n          : (expectedScheme == 'https' ? 443 : 80);\n      final client = httpClientFactory()\n        ..findProxy = (_) => 'DIRECT'\n        ..connectionFactory = (url, proxyHost, proxyPort) {\n          final targetScheme = url.scheme.toLowerCase();\n          final targetPort = url.hasPort\n              ? url.port\n              : (targetScheme == 'https' ? 443 : 80);\n          if (proxyHost != null ||\n              proxyPort != null ||\n              targetScheme != expectedScheme ||\n              url.host.toLowerCase() != expectedHost ||\n              targetPort != expectedPort) {\n            throw const WesiLocalRuntimePolicyException(\n              'WLR_SSRF_BLOCKED',\n              'HTTP connection не соответствует проверенному назначению',\n            );\n          }\n          // Connect by the already validated IP. HttpClient keeps the\n          // original HTTPS URI for TLS hostname/certificate validation.\n          return Socket.startConnect(pinnedAddress, targetPort);\n        };\n""",
)

print("Stage 6 hardening patch applied")
