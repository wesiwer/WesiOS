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

function preparedWithCoagent() {
  return {
    ...prepared(),
    tier: 'pro',
    route: 'wesi/pro',
    message: 'Сделай приложение с хорошим UX.',
    coagent: {
      enabled: true,
      reason: 'cross_domain_product',
      leadPersona: 'zane',
      coagentPersona: 'nirvana',
      task: 'Проверь UX/UI и верни структурированный результат.',
      context: [{kind: 'user_request', text: 'Сделай приложение с хорошим UX.'}],
      requestedCapabilities: ['tasks_list'],
      grantedCapabilities: ['tasks_list'],
      allowlistedCapabilities: ['tasks_list'],
      sideEffectCapabilities: [],
      allowedToolNames: ['tasks_list'],
      maxReviewRounds: 1,
      maxToolTurns: 0,
      systemPrompt: 'Ты Нирвана, Creative / Experience Persona Agent Wesi AI. '.repeat(5),
      toolDefinitions: [{name: 'tasks_list', wesiCapability: {risk: 'READ'}}],
    },
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
    if (String(url).endsWith('/api/wesi/ai/stream/prepare-v2')) {
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
    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'delta', 'delta', 'agent', 'done']);
    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Привет');
    assert.equal(JSON.stringify(events).includes('provider'), false);
  });
});

test('Co-Agent and Lead review stay buffered on same tier while Lead owns final answer', async () => {
  let relayCalls = 0;
  const relayPayloads = [];
  const rawCoagent = JSON.stringify({
    summary: 'UX review complete',
    findings: ['Упростить первый экран'],
    risks: ['Слишком много действий'],
    recommendation: 'Сократить первый экран',
    artifacts: [],
  });
  const fetchImpl = async (url, options) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare-v2')) {
      return jsonResponse({ok: true, prepared: preparedWithCoagent()});
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      const payload = JSON.parse(options.body);
      relayPayloads.push(payload);
      assert.equal(payload.route, 'wesi/pro');
      if (relayCalls === 1) {
        assert.equal(payload.input.system.includes('WESI_AI_PERSONA_COAGENT_HANDOFF'), true);
        return ndjson([
          {type: 'delta', text: rawCoagent.slice(0, 30)},
          {type: 'delta', text: rawCoagent.slice(30)},
          {type: 'done', answer: rawCoagent, provider: 'coagent-provider-must-not-leak'},
        ]);
      }
      if (relayCalls === 2) {
        assert.equal(payload.input.system.includes('WESI_AI_PERSONA_COAGENT_REVIEW'), true);
        const review = '{"decision":"accept"}';
        return ndjson([
          {type: 'delta', text: review},
          {type: 'done', answer: review, provider: 'review-provider-must-not-leak'},
        ]);
      }
      assert.equal(payload.input.system.includes('WESI_AI_VERIFIED_COAGENT_RESULT'), true);
      assert.equal(payload.input.system.includes('UX review complete'), true);
      return ndjson([
        {type: 'delta', text: 'Финал '},
        {type: 'delta', text: 'Зейна.'},
        {type: 'done', answer: 'Финал Зейна.', provider: 'lead-provider-must-not-leak'},
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
      body: JSON.stringify({persona: 'zane', tier: 'pro', message: 'Сделай приложение с хорошим UX.'}),
    });
    const events = await readEvents(response);
    assert.equal(relayCalls, 3);
    assert.equal(relayPayloads.every((payload) => payload.route === 'wesi/pro'), true);
    const coagentPhases = events.filter((event) => event.type === 'agent' && event.role === 'coagent').map((event) => event.phase);
    assert.deepEqual(coagentPhases, ['handoff', 'start', 'result', 'review']);
    const timeline = events.filter((event) => event.type === 'activity').map((event) => event.label);
    assert.equal(timeline.includes('Зейн → Нирвана'), true);
    assert.equal(timeline.includes('Нирвана · Co-Agent проверка'), true);
    assert.equal(timeline.includes('Нирвана → Зейн'), true);
    assert.equal(timeline.includes('Зейн · проверка Co-Agent результата'), true);
    assert.equal(timeline.includes('Зейн · результат принят'), true);
    const userText = events.filter((event) => event.type === 'delta').map((event) => event.text).join('');
    assert.equal(userText, 'Финал Зейна.');
    assert.equal(userText.includes('UX review complete'), false);
    assert.equal(userText.includes('decision'), false);
    assert.equal(events.at(-1).type, 'done');
    assert.equal(events.at(-1).answer, 'Финал Зейна.');
    assert.equal(JSON.stringify(events).includes('provider-must-not-leak'), false);
  });
});

test('tool JSON is never leaked and verified tool result precedes final stream', async () => {
  let relayCalls = 0;
  let toolCalls = 0;
  const toolJson = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
  const fetchImpl = async (url) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare-v2')) {
      return jsonResponse({ok: true, prepared: prepared()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool-v2')) {
      toolCalls += 1;
      return jsonResponse({
        ok: true,
        toolResult: {tool: 'tasks_list', verified: true, ok: true, result: {tasks: [], additions: 3, deletions: 1, files: ['lib/a.dart']}},
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
    const toolResultEvent = events.find((event) => event.type === 'tool' && event.phase === 'result');
    assert.equal(toolResultEvent.additions, 3);
    assert.equal(toolResultEvent.deletions, 1);
    assert.deepEqual(toolResultEvent.files, ['lib/a.dart']);
    const leadDone = events.find((event) => event.type === 'agent' && event.phase === 'result');
    assert.equal(leadDone.additions, 3);
    assert.equal(leadDone.deletions, 1);
    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Задач нет.');
    assert.equal(events.at(-1).type, 'done');
    assert.equal(events.at(-1).toolResults[0].verified, true);
  });
});

test('gateway health exposes ready state', async () => {
  const handler = createGateway({
    pocketBaseUrl: 'https://main.example.test',
    relayUrl: 'https://relay.example.test',
    streamSecret: 's'.repeat(40),
    relaySecret: 'r'.repeat(40),
    fetchImpl: async () => { throw new Error('not used'); },
  });
  const req = {method: 'GET', url: '/health'};
  let status = 0; let body = '';
  const res = {
    destroyed: false, writableEnded: false,
    writeHead(code) { status = code; },
    end(value='') { body += value; this.writableEnded = true; },
    write(value) { body += value; return true; },
    on() {},
  };
  await handler(req, res);
  assert.equal(status, 200);
  const json = JSON.parse(body);
  assert.equal(json.ready, true);
  assert.equal(json.streaming, true);
});
