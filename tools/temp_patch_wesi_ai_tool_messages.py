from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# 1) Gateway: send the already policy-safe executor message in live tool activity.
replace_once(
    'server/wesi-ai-stream/gateway.mjs',
    """          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n          additions: diff.additions,""",
    """          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n          message: toolResult?.message ? String(toolResult.message).slice(0, 1200) : null,\n          additions: diff.additions,""",
)

# 2) API: one canonical safe formatter for both live and verified results.
replace_once(
    'lib/features/ai/wesi_ai_api.dart',
    """      activity: _activityFromToolResults(json['toolResults']),\n    );\n  }\n\n  static List<Map<String, dynamic>> _activityFromToolResults(dynamic raw) {""",
    """      activity: toolActivityFromResults(json['toolResults']),\n    );\n  }\n\n  static String toolResultDetail(Map<dynamic, dynamic> raw) {\n    final code = '${raw['code'] ?? ''}'.trim();\n    final message = '${raw['message'] ?? ''}'.trim();\n    if (code.isEmpty) return message;\n    if (message.isEmpty || message == code) return code;\n    return '$code · $message';\n  }\n\n  static List<Map<String, dynamic>> toolActivityFromResults(dynamic raw) {""",
)
replace_once(
    'lib/features/ai/wesi_ai_api.dart',
    """      final tool = '${map['tool'] ?? map['name'] ?? ''}'.trim();\n      final filesRaw = payload['files'] ?? map['files'];""",
    """      final tool = '${map['tool'] ?? map['name'] ?? ''}'.trim();\n      final detail = toolResultDetail(map);\n      final filesRaw = payload['files'] ?? map['files'];""",
)
replace_once(
    'lib/features/ai/wesi_ai_api.dart',
    """        if (files.isNotEmpty) 'files': files,\n        if ('${map['code'] ?? ''}'.trim().isNotEmpty)\n          'detail': '${map['code']}',\n      });""",
    """        if (files.isNotEmpty) 'files': files,\n        if (detail.isNotEmpty) 'detail': detail,\n      });""",
)

# 3) Controller: keep safe human-readable detail in live activity and final merge.
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """      final files = raw['files'] is List\n          ? List<dynamic>.from(raw['files'] as List)\n          : const <dynamic>[];\n      if (type == 'tool') {""",
    """      final files = raw['files'] is List\n          ? List<dynamic>.from(raw['files'] as List)\n          : const <dynamic>[];\n      final toolDetail = type == 'tool' ? WesiAiApi.toolResultDetail(raw) : '';\n      if (type == 'tool') {""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """            final code = '${raw['code'] ?? ''}'.trim();\n            if (code.isNotEmpty) current['detail'] = code;\n            activity[index] = current;""",
    """            if (toolDetail.isNotEmpty) current['detail'] = toolDetail;\n            activity[index] = current;""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """              status: 'result',\n              additions: additions,\n              deletions: deletions,\n              files: files,""",
    """              status: 'result',\n              detail: toolDetail,\n              additions: additions,\n              deletions: deletions,\n              files: files,""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """              if (finalEvent['files'] is List)\n                next['files'] = List<dynamic>.from(finalEvent['files'] as List);\n              next['status'] = 'result';""",
    """              if (finalEvent['files'] is List)\n                next['files'] = List<dynamic>.from(finalEvent['files'] as List);\n              final finalDetail = '${finalEvent['detail'] ?? ''}'.trim();\n              if (finalDetail.isNotEmpty) next['detail'] = finalDetail;\n              next['status'] = 'result';""",
)

# 4) Flutter regression: verified error remains understandable to the user.
Path('test/wesi_ai_tool_result_detail_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('tool result detail keeps safe code and human-readable message', () {
    final detail = WesiAiApi.toolResultDetail(<String, dynamic>{
      'code': 'VALIDATION_ERROR',
      'message': 'Некорректная дата события',
    });
    expect(detail, 'VALIDATION_ERROR · Некорректная дата события');
  });

  test('verified tool activity keeps message after final response merge input', () {
    final activity = WesiAiApi.toolActivityFromResults(<Map<String, dynamic>>[
      <String, dynamic>{
        'tool': 'calendar_create',
        'verified': true,
        'ok': false,
        'code': 'VALIDATION_ERROR',
        'message': 'Некорректная дата события',
      },
    ]);
    expect(activity, hasLength(1));
    expect(activity.single['sourceName'], 'calendar_create');
    expect(
      activity.single['detail'],
      'VALIDATION_ERROR · Некорректная дата события',
    );
  });

  test('tool result detail does not duplicate identical code/message', () {
    expect(
      WesiAiApi.toolResultDetail(<String, dynamic>{
        'code': 'FORBIDDEN',
        'message': 'FORBIDDEN',
      }),
      'FORBIDDEN',
    );
  });
}
''', encoding='utf-8')

# 5) Gateway regression: live activity must carry the safe tool message too.
p = Path('server/wesi-ai-stream/tool_handoff.test.mjs')
text = p.read_text(encoding='utf-8')
needle = """test('malformed reserved tool envelope is hidden and repaired on the next model turn', async () => {"""
if needle not in text:
    raise SystemExit('tool_handoff insertion anchor missing')
new_test = r'''test('tool result activity carries safe executor message', async () => {
  let relayCalls = 0;
  const envelope = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool')) {
      return jsonResponse({
        ok: true,
        toolResult: {
          tool: 'tasks_list', verified: true, ok: false,
          code: 'VALIDATION_ERROR', message: 'Некорректный фильтр задач',
        },
      });
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      if (relayCalls === 1) return ndjson([{type: 'done', answer: envelope}]);
      return ndjson([{type: 'done', answer: 'Инструмент отклонил некорректный фильтр.'}]);
    }
    throw new Error(`unexpected URL ${url}`);
  };

  await withGateway(fetchImpl, async (base) => {
    const response = await fetch(`${base}/api/wesi/ai/chat/stream`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer user-token',
        'x-wesios-session': 'session_123456789012345678901234',
      },
      body: JSON.stringify({persona: 'zane', message: 'покажи задачи'}),
    });
    assert.equal(response.status, 200);
    const events = await readEvents(response);
    const result = events.find((event) => event.type === 'tool' && event.phase === 'result');
    assert.equal(result?.code, 'VALIDATION_ERROR');
    assert.equal(result?.message, 'Некорректный фильтр задач');
  });
});

'''
p.write_text(text.replace(needle, new_test + needle, 1), encoding='utf-8')

print('Wesi AI verified tool message patch applied')
