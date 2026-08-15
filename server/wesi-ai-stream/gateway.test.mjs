import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import {createGateway, parseToolRequest, shouldRevealBufferedText, signRelayRequest} from './gateway.mjs';

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

async function withGateway(fetchImpl, fn) {
  const server = http.createServer(createGateway({
    pocketBaseUrl: 'http://127.0.0.1:8090',
    relayUrl: 'https://relay.example.test',
    streamSecret: STREAM_SECRET,
    relaySecret: RELAY_SECRET,
    fetchImpl,
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    await fn(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function prepared() {
  return {
    requestId: 'wai_stream_test_1234567890',
    persona: 'zane',
    tier: 'fast',
    route: 'wesi/fast',
    operation: 'chat',
    systemParts: ['persona', '[WESI_AI_TOOL_PROTOCOL]\n[]'],
    history: [],
    message: 'привет',
    attachments: [],
    activeOrganizationId: 'org_wesi_inc',
    conversationId: 'chat-1',
    toolNames: ['tasks_list'],
  };
}

async function readEvents(response) {
  const text = await response.text();
  return text.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
}

test('tool parser accepts only structured Wesi tool envelope', () => {
  assert.deepEqual(
    parseToolRequest('{"wesiTool":{"name":"tasks_list","arguments":{"limit":3}}}'),
    {name: 'tasks_list', arguments: {limit: 3}},
  );
  assert.equal(parseToolRequest('Обычный ответ'), null);
});

test('stream sniffer reveals normal text but withholds tool JSON', () => {
  assert.equal(shouldRevealBufferedText('Привет'), true);
  assert.equal(shouldRevealBufferedText('{"wesiTool":'), false);
  assert.equal(shouldRevealBufferedText('```json\n{"wesiTool":'), false);
});

test('HMAC signing matches deterministic payload', () => {
  const actual = signRelayRequest('rid', '123', '{"x":1}', 'secret');
  assert.equal(actual, '00869641839c4678dd4316b6a4d07ced9cdd8b44751bb15286e4665e39093a78');
});

test('gateway forwards true deltas and final done event without provider metadata', async () => {
  let relayCalls = 0;
  const fetchImpl = async (url, options) => {
    if (String(url).endsWith('/api/wesi/ai/stream/prepare')) {
      assert.equal(options.headers.authorization, 'Bearer user-token');
      assert.equal(options.headers['x-wesios-session'], 'session_123456789012345678901234');
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (String(url).endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      return ndjson([
        {type: 'delta', text: 'При'},
        {type: 'delta', text: 'вет'},
        {type: 'done', answer: 'Привет', provider: 'must-not-leak'},
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
      body: JSON.stringify({persona: 'zane', message: 'привет'}),
    });
    assert.equal(response.status, 200);
    const events = await readEvents(response);
    assert.equal(relayCalls, 1);
    assert.deepEqual(events.map((event) => event.type), ['meta', 'delta', 'delta', 'done']);
    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Привет');
    assert.equal(JSON.stringify(events).includes('provider'), false);
  });
});

test('tool JSON is never leaked and verified tool result precedes final stream', async () => {
  let relayCalls = 0;
  let toolCalls = 0;
  const toolJson = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool')) {
      toolCalls += 1;
      return jsonResponse({
        ok: true,
        toolResult: {tool: 'tasks_list', verified: true, ok: true, result: {tasks: []}},
      });
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      if (relayCalls === 1) {
        return ndjson([
          {type: 'delta', text: toolJson.slice(0, 20)},
          {type: 'delta', text: toolJson.slice(20)},
          {type: 'done', answer: toolJson},
        ]);
      }
      return ndjson([
        {type: 'delta', text: 'Задач '},
        {type: 'delta', text: 'нет.'},
        {type: 'done', answer: 'Задач нет.'},
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
    assert.equal(toolCalls, 1);
    assert.equal(events.some((event) => event.type === 'delta' && String(event.text).includes('wesiTool')), false);
    assert.deepEqual(
      events.filter((event) => event.type === 'tool').map((event) => event.phase),
      ['start', 'result'],
    );
    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Задач нет.');
    assert.equal(events.at(-1).type, 'done');
    assert.equal(events.at(-1).toolResults[0].verified, true);
  });
});
