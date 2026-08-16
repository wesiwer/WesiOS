from pathlib import Path

path = Path('server/wesi-ai-stream/gateway.test.mjs')
text = path.read_text()
old = "    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'delta', 'delta', 'agent', 'done']);\n"
new = "    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'delta', 'agent', 'done']);\n"
if new not in text:
    if text.count(old) != 1:
        raise SystemExit(f'gateway delta expectation: expected one marker, found {text.count(old)}')
    text = text.replace(old, new, 1)
path.write_text(text)
