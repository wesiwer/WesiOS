import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import {
  createGateway,
  hasToolProtocolMarker,
  parseToolRequest,
  shouldRevealBufferedText,
} from './gateway.mjs';

const STREAM_SECRET = 's'.repeat(64);
const RELAY_SECRET = 'r'.repeat(64);

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {'content-type': 'application/json'},
  });
}

function ndjson(events) {
  return new Response(events.map((event) => JSON.stringify(event)).join('\n') + '\n', {
    status: 200,
    headers: {'content-type': 'application/x-ndjson'},
  });
}

function prepared() {
  return {
    requestId: 'wai_stream_tool_handoff_test',
    persona: 'zane',
    tier: 'fast',
    route: 'wesi/fast',
    operation: 'chat',
    systemParts: ['persona', '[WESI_AI_TOOL_PROTOCOL]\n[]'],
    history: [],
    message: 'покажи задачи',
    attachments: [],
    activeOrganizationId: 'org_wesi_inc',
    conversationId: 'chat-tool-handoff',
    toolNames: ['tasks_list'],
  };
}

async function withGateway(fetchImpl, fn) {
  const server = http.createServer(createGateway({
    pocketBaseUrl: 'http://127.0.0.1:8090',
    relayUrl: 'https://relay.example.test',
    streamSecret: STREAM_SECRET,
    relaySecret: RELAY_SECRET,
    fetchImpl,
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await fn(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function readEvents(response) {
  const raw = await response.text();
  return raw.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
}

test('tool parser tolerates provider wrappers but rejects examples', () => {
  const expected = {name: 'tasks_list', arguments: {limit: 2}};
  const envelope = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';

  assert.deepEqual(parseToolRequest(envelope), expected);
  assert.deepEqual(parseToolRequest(`\`\`\`json\n${envelope}\n\`\`\``), expected);
  assert.deepEqual(parseToolRequest(`<think>need live tasks</think>\n${envelope}`), expected);
  assert.deepEqual(parseToolRequest(`Сейчас проверю через инструмент:\n${envelope}`), expected);
  assert.equal(parseToolRequest(`Например, формат вызова инструмента:\n${envelope}`), null);
  assert.equal(hasToolProtocolMarker(envelope), true);
  assert.equal(hasToolProtocolMarker('Обычный ответ без служебного вызова'), false);
});

test('stream classifier withholds a partial tool envelope until it is classified', () => {
  assert.equal(shouldRevealBufferedText('{"wesi'), false);
  assert.equal(shouldRevealBufferedText('{"wesiTool":'), false);
  assert.equal(shouldRevealBufferedText('{"answer":"обычный JSON"}'), true);
});

test('wrapped tool JSON is executed but never streamed to the user', async () => {
  let relayCalls = 0;
  let toolCalls = 0;
  const envelope = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
  const wrapped = `Сейчас проверю через инструмент:\n${envelope}`;

  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool')) {
      toolCalls += 1;
      return jsonResponse({
        ok: true,
        toolResult: {
          tool: 'tasks_list',
          verified: true,
          ok: true,
          result: {tasks: [{id: 'task-1', title: 'Проверить handoff'}]},
        },
      });
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      if (relayCalls === 1) {
        return ndjson([
          {type: 'delta', text: 'Сейчас проверю через инструмент:\n'},
          {type: 'delta', text: envelope.slice(0, 18)},
          {type: 'delta', text: envelope.slice(18)},
          {type: 'done', answer: wrapped},
        ]);
      }
      return ndjson([
        {type: 'delta', text: 'Нашёл одну задачу.'},
        {type: 'done', answer: 'Нашёл одну задачу.'},
      ]);
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
    assert.equal(relayCalls, 2);
    assert.equal(toolCalls, 1);
    assert.equal(events.some((event) => event.type === 'delta' && String(event.text).includes('wesiTool')), false);
    assert.deepEqual(events.filter((event) => event.type === 'tool').map((event) => event.phase), ['start', 'result']);
    const done = events.at(-1);
    assert.equal(done.type, 'done');
    assert.equal(done.answer, 'Нашёл одну задачу.');
    assert.equal(done.toolResults[0].verified, true);
  });
});

test('tool result activity carries safe executor message', async () => {
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
      if (relayCalls === 1) return ndjson([{type: 'delta', text: envelope}, {type: 'done', answer: envelope}]);
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

test('malformed reserved tool envelope is hidden and repaired on the next model turn', async () => {
  let relayCalls = 0;
  let toolCalls = 0;
  const malformed = 'Сейчас проверю:\n{"wesiTool":{"name":"tasks_list","arguments":oops}}';

  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool')) {
      toolCalls += 1;
      throw new Error('malformed protocol must not reach tool executor');
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      if (relayCalls === 1) {
        return ndjson([
          {type: 'delta', text: malformed},
          {type: 'done', answer: malformed},
        ]);
      }
      return ndjson([
        {type: 'delta', text: 'Не смог корректно вызвать инструмент и не выполнял действие.'},
        {type: 'done', answer: 'Не смог корректно вызвать инструмент и не выполнял действие.'},
      ]);
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
    const events = await readEvents(response);
    assert.equal(relayCalls, 2);
    assert.equal(toolCalls, 0);
    assert.equal(events.some((event) => event.type === 'delta' && String(event.text).includes('wesiTool')), false);
    const protocolEvent = events.find((event) => event.type === 'tool' && event.name === 'wesi_tool_protocol');
    assert.equal(protocolEvent?.code, 'INVALID_TOOL_CALL');
    const done = events.at(-1);
    assert.equal(done.type, 'done');
    assert.equal(done.toolResults[0].code, 'INVALID_TOOL_CALL');
  });
});
