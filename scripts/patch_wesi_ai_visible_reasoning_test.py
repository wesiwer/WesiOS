from pathlib import Path

p = Path('server/wesi-ai-stream/gateway.test.mjs')
text = p.read_text(encoding='utf-8')
old = "    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'delta', 'delta', 'agent', 'done']);\n    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Привет');\n"
new = "    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'activity', 'delta', 'delta', 'agent', 'done']);\n    const visibleReasoning = events.find((event) => event.type === 'activity' && event.label === 'Как я подхожу к запросу');\n    assert.ok(visibleReasoning);\n    assert.match(String(visibleReasoning.detail || ''), /приветств/i);\n    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Привет');\n"
if text.count(old) != 1:
    raise SystemExit(f'expected one gateway event assertion, got {text.count(old)}')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
print('VISIBLE_REASONING_EVENT_TEST_PATCH_APPLIED')
