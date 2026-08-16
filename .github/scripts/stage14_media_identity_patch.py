from pathlib import Path

path = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
text = path.read_text()

marker = '''  void _startPendingMedia(\n    WesiAiMessage message, {\n'''
helper = '''  String _localMediaRequestIdentity(Map<String, dynamic> request) {\n    final rawIndexes = request['attachmentIndexes'];\n    final indexes = rawIndexes is List\n        ? rawIndexes.map((item) => '$item').join(',')\n        : '';\n    return <String>[\n      '${request['mediaType'] ?? ''}',\n      '${request['workflow'] ?? ''}',\n      '${request['prompt'] ?? ''}',\n      '${request['title'] ?? ''}',\n      indexes,\n    ].join('|');\n  }\n\n  void _startPendingMedia(\n    WesiAiMessage message, {\n'''
if text.count(marker) != 1:
    raise SystemExit(f'identity helper marker count={text.count(marker)}')
text = text.replace(marker, helper, 1)

old_key = '''        final key =\n            '${message.id}|local|${data['mediaType']}|${data['prompt']}';\n'''
new_key = '''        final requestMap = Map<String, dynamic>.from(localRequest);\n        final key =\n            '${message.id}|local|${_localMediaRequestIdentity(requestMap)}';\n'''
if text.count(old_key) != 1:
    raise SystemExit(f'local key marker count={text.count(old_key)}')
text = text.replace(old_key, new_key, 1)
text = text.replace('''            Map<String, dynamic>.from(localRequest),\n            key,\n''', '''            requestMap,\n            key,\n''', 1)

method_marker = '''  Future<void> _markLocalRequestFinished(\n    String messageId,\n    Map<String, dynamic> request,\n    bool ok,\n  ) async {\n    var changed = false;\n'''
method_new = '''  Future<void> _markLocalRequestFinished(\n    String messageId,\n    Map<String, dynamic> request,\n    bool ok,\n  ) async {\n    final targetIdentity = _localMediaRequestIdentity(request);\n    var changed = false;\n'''
if text.count(method_marker) != 1:
    raise SystemExit(f'mark method marker count={text.count(method_marker)}')
text = text.replace(method_marker, method_new, 1)

old_match = '''            if (localRaw is Map &&\n                '${localRaw['mediaType'] ?? ''}' ==\n                    '${request['mediaType'] ?? ''}' &&\n                '${localRaw['prompt'] ?? ''}' == '${request['prompt'] ?? ''}') {\n'''
new_match = '''            if (localRaw is Map &&\n                _localMediaRequestIdentity(\n                      Map<String, dynamic>.from(localRaw),\n                    ) ==\n                    targetIdentity) {\n'''
if text.count(old_match) != 1:
    raise SystemExit(f'mark matcher count={text.count(old_match)}')
text = text.replace(old_match, new_match, 1)

path.write_text(text)
