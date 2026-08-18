import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';

import {
  createGateway,
  MAX_RUN_DEADLINE_MS_HARD_CAP,
  MAX_RUN_STEPS_HARD_CAP,
  runBudget,
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

function preparedLongRun() {
  return {
    requestId: 'wai_long_run_test_1234567890',
    persona: 'zane',
    tier: 'maximum',
    route: 'wesi/maximum',
    operation: 'chat',
    systemParts: [
      'persona',
      '[WESI_AI_TOOL_PROTOCOL]\nUse verified tools until the task is actually complete.',
      '[WESI_AI_LONG_RUN]\nContinue autonomously; do not ask the user to say continue.',
    ],
    history: [],
    message: 'Проверь шесть независимых частей и доведи работу до конца самостоятельно.',
    attachments: [],
    activeOrganizationId: 'org_wesi_inc',
    conversationId: 'chat-long-run',
    toolNames: ['tasks_list'],
    run: {
      maxSteps: 40,
      deadlineMs: 20 * 60 * 1000,
      maxStalledSteps: 4,
      autonomous: true,
    },
  };
}

async function withGateway(fetchImpl, fn) {
  const server = http.createServer(createGateway({
    pocketBaseUrl: 'http://127.0.0.1:8090',
    relayUrl: 'https://relay.example.test',
    streamSecret: STREAM_SECRET,
    relaySecret: RELAY_SECRET,
    fetchImpl,
    publicDeliberation: false,
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    await fn(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function readEvents(response) {
  const text = await response.text();
  return text.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
}

test('maximum tier performs more than four verified tool turns without user continuation', async () => {
  let relayCalls = 0;
  let toolCalls = 0;
  const toolRequests = [];

  const fetchImpl = async (url, options = {}) => {
    const value = String(url);
    if (value.endsWith('/api/wesi/ai/stream/prepare-v2')) {
      return jsonResponse({ok: true, prepared: preparedLongRun()});
    }
    if (value.endsWith('/api/wesi/ai/stream/tool-v2')) {
      toolCalls += 1;
      const body = JSON.parse(options.body || '{}');
      toolRequests.push(body);
      return jsonResponse({
        ok: true,
        toolResult: {
          tool: 'tasks_list',
          verified: true,
          ok: true,
          result: {checkpoint: toolCalls},
          capability: {module: 'tasks', action: 'read', risk: 'READ', mutation: false},
        },
      });
    }
    if (value.endsWith('/v1/wesi-ai-stream')) {
      relayCalls += 1;
      if (relayCalls <= 6) {
        const answer = JSON.stringify({
          wesiTool: {name: 'tasks_list', arguments: {checkpoint: relayCalls}},
        });
        return ndjson([{type: 'done', answer}]);
      }
      return ndjson([
        {type: 'delta', text: 'Все шесть проверок завершены. '},
        {type: 'delta', text: 'Дополнительного сообщения «продолжай» не потребовалось.'},
        {type: 'done', answer: 'Все шесть проверок завершены. Дополнительного сообщения «продолжай» не потребовалось.'},
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
      body: JSON.stringify({
        persona: 'zane',
        tier: 'maximum',
        message: 'Проведи длинную проверку самостоятельно.',
      }),
    });

    assert.equal(response.status, 200);
    const events = await readEvents(response);
    assert.equal(toolCalls, 6, 'long run stopped at the old four-turn ceiling');
    assert.equal(relayCalls, 7);
    assert.deepEqual(toolRequests.map((item) => item.arguments?.checkpoint), [1, 2, 3, 4, 5, 6]);
    assert.equal(events.filter((event) => event.type === 'tool' && event.phase === 'result').length, 6);
    assert.equal(events.at(-1)?.type, 'done');
    assert.match(String(events.at(-1)?.answer || ''), /шесть проверок завершены/i);
    assert.equal(JSON.stringify(events).includes('скажи «продолжай»'), false);
  });
});

test('gateway clamps an untrusted run policy to hard safety caps', () => {
  const budget = runBudget({
    run: {
      maxSteps: 999999,
      deadlineMs: 24 * 60 * 60 * 1000,
      maxStalledSteps: 7,
      autonomous: true,
    },
  });
  assert.equal(budget.maxSteps, MAX_RUN_STEPS_HARD_CAP);
  assert.equal(budget.deadlineMs, MAX_RUN_DEADLINE_MS_HARD_CAP);
  assert.equal(budget.maxStalledSteps, 7);
  assert.equal(budget.autonomous, true);
});

test('invalid run policy falls back to bounded defaults instead of becoming unbounded', () => {
  const budget = runBudget({
    run: {maxSteps: -10, deadlineMs: 0, maxStalledSteps: -1, autonomous: true},
  });
  assert.equal(budget.maxSteps, 4);
  assert.equal(budget.deadlineMs, MAX_RUN_DEADLINE_MS_HARD_CAP);
  assert.equal(budget.maxStalledSteps, 3);
});
