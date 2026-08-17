from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, found {count}: {old!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/features/ai/wesi_ai_api.dart',
    '      if (thinkingMode && conversation.persona != WesiAiPersona.lobby) {',
    "      // Classic and Thinking both use the full orchestration pipeline.\n"
    "      // thinkingMode controls only extra public deliberation checkpoints.\n"
    "      if (conversation.persona != WesiAiPersona.lobby) {",
)

replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    "    void onActivity(Map<String, dynamic> raw) {\n      final type = '${raw['type'] ?? 'activity'}'.toLowerCase();",
    "    void onActivity(Map<String, dynamic> raw) {\n"
    "      // Classic keeps agents/tools/subagents on the server, but does not\n"
    "      // expose their activity/reasoning timeline in the conversation UI.\n"
    "      if (!thinkingMode) return;\n"
    "      final type = '${raw['type'] ?? 'activity'}'.toLowerCase();",
)

replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    "      final completedAt = DateTime.now().toUtc().toIso8601String();",
    "      // Tool results can still arrive in the final stream payload. Keep\n"
    "      // them available to the response parser, but do not surface the\n"
    "      // visible activity block in Classic mode.\n"
    "      if (!thinkingMode) activity.clear();\n"
    "      final completedAt = DateTime.now().toUtc().toIso8601String();",
)

replace_once(
    'server/wesi-ai-stream/gateway.mjs',
    '      if (!deliberationState) {',
    '      if (thinkingMode && !deliberationState) {',
)

# Add a regression test: Classic must not spend a model call on public
# deliberation, while still using the streaming orchestration endpoint.
test_path = Path('server/wesi-ai-stream/gateway.test.mjs')
test_text = test_path.read_text(encoding='utf-8')
marker = "test('gateway health exposes ready state', async () => {"
if marker not in test_text:
    raise SystemExit('gateway test insertion marker not found')
new_test = r'''
test('classic mode keeps streaming orchestration but skips public deliberation', async () => {
  let relayCalls = 0;
  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare-v2')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      return ndjson([{type: 'done', answer: 'Быстрый полноценный ответ.'}]);
    }
    throw new Error(`unexpected URL ${url}`);
  };
  const server = http.createServer(createGateway({
    pocketBaseUrl: 'http://127.0.0.1:8090',
    relayUrl: 'https://relay.example.test',
    streamSecret: STREAM_SECRET,
    relaySecret: RELAY_SECRET,
    fetchImpl,
    publicDeliberation: true,
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/api/wesi/ai/chat/stream`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer user-token',
        'x-wesios-session': 'session_123456789012345678901234',
      },
      body: JSON.stringify({persona: 'zane', message: 'быстро проверь', thinkingMode: false}),
    });
    assert.equal(response.status, 200);
    const events = await readEvents(response);
    assert.equal(relayCalls, 1, 'Classic must not add a deliberation model call');
    assert.equal(events.some((event) => event.publicDeliberation === true), false);
    assert.equal(events.at(-1).type, 'done');
    assert.equal(events.at(-1).answer, 'Быстрый полноценный ответ.');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

'''
test_path.write_text(test_text.replace(marker, new_test + marker, 1), encoding='utf-8')

replace_once('pubspec.yaml', 'version: 0.22.21+96', 'version: 0.22.22+97')
replace_once(
    'lib/core/constants/app_version.dart',
    "  static const String number = '0.22.21';",
    "  static const String number = '0.22.22';",
)
replace_once(
    'lib/core/constants/app_version.dart',
    '  static const int build = 96;',
    '  static const int build = 97;',
)

print('CLASSIC_FULL_ORCHESTRATION_PATCH_APPLIED 0.22.22+97')
