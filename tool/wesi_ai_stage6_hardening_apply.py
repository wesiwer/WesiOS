from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"patch anchor missing in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Workspace internal-state and IPv4-mapped IPv6 guards were already applied by
# the preceding one-shot SSRF hardening commit. This patch only contains the
# remaining compile/visibility/connection-target hardening.
policy = ROOT / "lib/features/ai/runtime/wesi_local_runtime_policy.dart"
replace_once(policy, "    if (uri.hasUserInfo) {\n", "    if (uri.userInfo.isNotEmpty) {\n")

executor = ROOT / "lib/features/ai/runtime/wesi_local_runtime_executor.dart"
replace_once(
    executor,
    """    await for (final entity in Directory(path).list(followLinks: false)) {\n      if (entries.length >= context.limits.maxDirectoryEntries) {\n""",
    """    await for (final entity in Directory(path).list(followLinks: false)) {\n      // `.wesi` stores runtime HOME/tmp/hooks/audit and is deliberately not\n      // part of the model-visible workspace namespace.\n      if (p.equals(path, root) &&\n          p.basename(entity.path).toLowerCase() == '.wesi') {\n        continue;\n      }\n      if (entries.length >= context.limits.maxDirectoryEntries) {\n""",
)
replace_once(
    executor,
    """      if (!recursive && await Directory(path).list(followLinks: false).isNotEmpty) {\n""",
    """      if (!recursive &&\n          !(await Directory(path).list(followLinks: false).isEmpty)) {\n""",
)
replace_once(
    executor,
    """      final pinnedAddress = addresses.first;\n      final expectedHost = requestUri.host.toLowerCase();\n      final client = httpClientFactory()\n        ..findProxy = (_) => 'DIRECT'\n        ..connectionFactory = (url, proxyHost, proxyPort) {\n          if (proxyHost != null || proxyPort != null ||\n              url.host.toLowerCase() != expectedHost) {\n            throw const WesiLocalRuntimePolicyException(\n              'WLR_SSRF_BLOCKED',\n              'HTTP connection не соответствует проверенному назначению',\n            );\n          }\n          final port = url.hasPort\n              ? url.port\n              : (url.scheme.toLowerCase() == 'https' ? 443 : 80);\n          return Socket.startConnect(pinnedAddress, port);\n        };\n""",
    """      final pinnedAddress = addresses.first;\n      final expectedScheme = requestUri.scheme.toLowerCase();\n      final expectedHost = requestUri.host.toLowerCase();\n      final expectedPort = requestUri.hasPort\n          ? requestUri.port\n          : (expectedScheme == 'https' ? 443 : 80);\n      final client = httpClientFactory()\n        ..findProxy = (_) => 'DIRECT'\n        ..connectionFactory = (url, proxyHost, proxyPort) {\n          final targetScheme = url.scheme.toLowerCase();\n          final targetPort = url.hasPort\n              ? url.port\n              : (targetScheme == 'https' ? 443 : 80);\n          if (proxyHost != null ||\n              proxyPort != null ||\n              targetScheme != expectedScheme ||\n              url.host.toLowerCase() != expectedHost ||\n              targetPort != expectedPort) {\n            throw const WesiLocalRuntimePolicyException(\n              'WLR_SSRF_BLOCKED',\n              'HTTP connection не соответствует проверенному назначению',\n            );\n          }\n          // Socket uses the already validated address; the request URI keeps\n          // the original HTTPS hostname for normal HttpClient TLS validation.\n          return Socket.startConnect(pinnedAddress, targetPort);\n        };\n""",
)

print("Stage 6 remaining hardening patch applied")
