from pathlib import Path

p = Path('lib/core/sync/pocketbase_transport.dart')
text = p.read_text(encoding='utf-8')
old = '''  static String revisionFromResponse(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final stamp = '${first['stamp'] ?? ''}';
    return '$id|$stamp';
  }'''
new = '''  static String revisionFromResponse(Map<String, dynamic> json) {
    // Current legacy WesiOS hook already returns the same compact revision
    // string as revision-v2. Accept it first so a rolling deploy fallback is
    // genuinely live instead of silently collapsing every response to empty.
    final direct = json['revision'];
    if (direct is String && direct.isNotEmpty) return direct;

    // Older pre-gateway responses exposed the newest record through items.
    // Keep this parser for backwards compatibility with those installations
    // and with migration fixtures.
    final items = json['items'];
    if (items is! List || items.isEmpty) return 'empty';
    final first = items.first;
    if (first is! Map) return 'empty';
    final id = '${first['id'] ?? ''}';
    final stamp = '${first['stamp'] ?? ''}';
    return '$id|$stamp';
  }'''
if text.count(old) != 1:
    raise SystemExit(f'revisionFromResponse anchor count={text.count(old)}')
p.write_text(text.replace(old, new, 1), encoding='utf-8')

t = Path('test/sync_revision_fallback_test.dart')
t.write_text('''import 'package:flutter_test/flutter_test.dart';\nimport 'package:wesios/core/sync/pocketbase_transport.dart';\n\nvoid main() {\n  test('legacy revision fallback accepts current compact server response', () {\n    expect(\n      PocketBaseTransport.revisionFromResponse(\n        <String, dynamic>{'revision': 'record|2026-08-17T20:00:00Z'},\n      ),\n      'record|2026-08-17T20:00:00Z',\n    );\n  });\n\n  test('legacy revision fallback still accepts historical items response', () {\n    expect(\n      PocketBaseTransport.revisionFromResponse(<String, dynamic>{\n        'items': <Object>[\n          <String, dynamic>{\n            'id': 'abc',\n            'stamp': '2026-08-17T19:00:00Z',\n          },\n        ],\n      }),\n      'abc|2026-08-17T19:00:00Z',\n    );\n  });\n\n  test('legacy revision fallback keeps empty semantics', () {\n    expect(PocketBaseTransport.revisionFromResponse(<String, dynamic>{}), 'empty');\n  });\n}\n''', encoding='utf-8')
print('SYNC_REVISION_FALLBACK_PATCH_READY')
