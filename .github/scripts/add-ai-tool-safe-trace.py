from pathlib import Path

p = Path('server/wesi-ai-stream/gateway.mjs')
text = p.read_text(encoding='utf-8')

anchor = "export const MAX_TOOL_TURNS = 4;\n"
helper = '''export const MAX_TOOL_TURNS = 4;\n\nfunction toolTrace(event, fields = {}) {\n  const safe = {\n    event: `wesi_ai_tool_${String(event || 'event')}`,\n    at: new Date().toISOString(),\n  };\n  for (const key of ['requestId', 'phase', 'tool', 'code', 'persona']) {\n    const value = fields[key];\n    if (value !== undefined && value !== null && String(value).trim()) {\n      safe[key] = String(value).slice(0, 180);\n    }\n  }\n  if (fields.ok !== undefined) safe.ok = fields.ok === true;\n  if (Number.isFinite(Number(fields.toolCount))) safe.toolCount = Number(fields.toolCount);\n  // Never log prompts, messages, arguments, tool results, credentials or session data.\n  console.info(JSON.stringify(safe));\n}\n'''
if text.count(anchor) != 1:
    raise SystemExit('MAX_TOOL_TURNS anchor not found exactly once')
text = text.replace(anchor, helper, 1)

anchor = '''      const toolResults = [];
      const seenCalls = new Set();'''
replacement = '''      toolTrace('prepare', {
        requestId: prepared.requestId,
        persona: prepared.persona,
        phase: 'lead',
        toolCount: Array.isArray(prepared.toolDefinitions) ? prepared.toolDefinitions.length : 0,
      });
      const toolResults = [];
      const seenCalls = new Set();'''
if text.count(anchor) != 1:
    raise SystemExit('tool loop prepare anchor not found exactly once')
text = text.replace(anchor, replacement, 1)

anchor = '''          if (streamed.invalidToolProtocol) {
            toolResults.push({'''
replacement = '''          if (streamed.invalidToolProtocol) {
            toolTrace('invalid_protocol', {
              requestId: prepared.requestId,
              persona: prepared.persona,
              phase: String(turn + 1),
              code: 'INVALID_TOOL_CALL',
              ok: false,
            });
            toolResults.push({'''
if text.count(anchor) != 1:
    raise SystemExit('invalid protocol anchor not found exactly once')
text = text.replace(anchor, replacement, 1)

anchor = '''          seenCalls.add(signature);
          writeNdjson(res, {type: 'tool', phase: 'start', name: toolRequest.name});'''
replacement = '''          seenCalls.add(signature);
          toolTrace('start', {
            requestId: prepared.requestId,
            persona: prepared.persona,
            phase: String(turn + 1),
            tool: toolRequest.name,
          });
          writeNdjson(res, {type: 'tool', phase: 'start', name: toolRequest.name});'''
if text.count(anchor) != 1:
    raise SystemExit('tool start anchor not found exactly once')
text = text.replace(anchor, replacement, 1)

anchor = '''        toolResults.push(toolResult);
        const diff = diffStatsFromToolResult(toolResult);'''
replacement = '''        toolResults.push(toolResult);
        toolTrace('result', {
          requestId: prepared.requestId,
          persona: prepared.persona,
          phase: String(turn + 1),
          tool: toolRequest.name,
          ok: toolResult?.ok === true,
          code: toolResult?.code || (toolResult?.ok === true ? 'OK' : 'WAI_TOOL_FAILED'),
        });
        const diff = diffStatsFromToolResult(toolResult);'''
if text.count(anchor) != 1:
    raise SystemExit('tool result anchor not found exactly once')
text = text.replace(anchor, replacement, 1)

p.write_text(text, encoding='utf-8')

t = Path('server/wesi-ai-stream/gateway.test.mjs')
test_text = t.read_text(encoding='utf-8')
anchor = "test('stream sniffer reveals normal text but withholds tool JSON', () => {"
extra = '''test('tool parser tolerates bounded service chatter but not arbitrary prose', () => {\n  assert.deepEqual(\n    parseToolRequest('Проверяю через инструмент. {"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}'),\n    {name: 'tasks_list', arguments: {limit: 2}},\n  );\n  assert.deepEqual(\n    parseToolRequest('```json\\n{"wesiTool":{"name":"finance_summary","arguments":{}}}\\n```'),\n    {name: 'finance_summary', arguments: {}},\n  );\n  assert.equal(\n    parseToolRequest('Например, вот формат вызова: {"wesiTool":{"name":"tasks_list","arguments":{}}}'),\n    null,\n  );\n});\n\n'''
if anchor not in test_text:
    raise SystemExit('gateway parser test anchor not found')
test_text = test_text.replace(anchor, extra + anchor, 1)
t.write_text(test_text, encoding='utf-8')

print('SAFE_TOOL_TRACE_PATCH_READY')
