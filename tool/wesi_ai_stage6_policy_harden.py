from pathlib import Path

path = Path('lib/features/ai/runtime/wesi_local_runtime_policy.dart')
text = path.read_text(encoding='utf-8')

old_paths = '''    if (segments.any((segment) => segment == '..')) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_PATH_ESCAPE',
        'Выход за пределы workspace запрещён',
      );
    }

    final candidate = p.normalize(p.absolute(p.join(root, relative)));
'''
new_paths = '''    if (segments.any((segment) => segment == '..')) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_PATH_ESCAPE',
        'Выход за пределы workspace запрещён',
      );
    }
    final visibleSegments = segments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (visibleSegments.isNotEmpty &&
        visibleSegments.first.toLowerCase() == '.wesi') {
      throw const WesiLocalRuntimePolicyException(
        'WLR_INTERNAL_PATH_FORBIDDEN',
        'Внутреннее состояние local runtime недоступно через model tool calls',
      );
    }

    final candidate = p.normalize(p.absolute(p.join(root, relative)));
'''
if old_paths not in text:
    raise SystemExit('workspace path anchor missing')
text = text.replace(old_paths, new_paths, 1)

old_v4 = '''      if (a == 192 && b == 168) return true;
      if (a == 198 && (b == 18 || b == 19)) return true;
      if (a >= 224) return true;
      return false;
'''
new_v4 = '''      final c = bytes[2];
      if (a == 192 && b == 168) return true;
      if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
      if (a == 192 && b == 88 && c == 99) return true;
      if (a == 198 && (b == 18 || b == 19)) return true;
      if (a == 198 && b == 51 && c == 100) return true;
      if (a == 203 && b == 0 && c == 113) return true;
      if (a >= 224) return true;
      return false;
'''
if old_v4 not in text:
    raise SystemExit('IPv4 anchor missing')
text = text.replace(old_v4, new_v4, 1)

old_v6 = '''      final loopback = bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
      if (loopback) return true;
      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local
'''
new_v6 = '''      final loopback = bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
      if (loopback) return true;
      final ipv4Mapped = bytes.take(10).every((value) => value == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (ipv4Mapped) {
        final a = bytes[12];
        final b = bytes[13];
        final c = bytes[14];
        if (a == 0 || a == 10 || a == 127) return true;
        if (a == 100 && b >= 64 && b <= 127) return true;
        if (a == 169 && b == 254) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 192 && b == 168) return true;
        if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
        if (a == 192 && b == 88 && c == 99) return true;
        if (a == 198 && (b == 18 || b == 19)) return true;
        if (a == 198 && b == 51 && c == 100) return true;
        if (a == 203 && b == 0 && c == 113) return true;
        if (a >= 224) return true;
        return false;
      }
      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local
'''
if old_v6 not in text:
    raise SystemExit('IPv6 anchor missing')
text = text.replace(old_v6, new_v6, 1)

path.write_text(text, encoding='utf-8')
print('Hardened Wesi Local workspace and SSRF policy')
