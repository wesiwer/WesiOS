import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCoagentToolRequest, runPersonaCoagent} from './persona_coagent_orchestrator.mjs';

function prepared(overrides = {}) {
  return {
    requestId: 'wai_stage12_test',
    persona: 'zane',
    tier: 'pro',
    route: 'wesi/pro',
    activeOrganizationId: 'org-1',
    conversationId: 'chat-1',
    coagent: {
      enabled: true,
      reason: 'creative_review_needed',
      leadPersona: 'zane',
      coagentPersona: 'nirvana',
      task: 'Проверь UX/UI.',
      context: [{kind: 'user_request', text: 'Сделай приложение с хорошим UX.'}],
      requestedCapabilities: ['tasks_list'],
      grantedCapabilities: ['tasks_list'],
      allowlistedCapabilities: ['tasks_list'],
      sideEffectCapabilities: ['tasks_create'],
      allowedToolNames: ['tasks_list'],
      maxReviewRounds: 1,
      maxToolTurns: 2,
      systemPrompt: 'Ты Нирвана, Creative / Experience Persona Agent Wesi AI. '.repeat(5),
      toolDefinitions: [{name: 'tasks_list', wesiCapability: {risk: 'READ'}}],
    },
    ...overrides,
  };
}

test('Co-Agent tool parser accepts exact service envelope only', () => {
  assert.deepEqual(
    parseCoagentToolRequest('{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}'),
    {name: 'tasks_list', arguments: {limit: 2}},
  );
  assert.equal(parseCoagentToolRequest('Обычный текст'), null);
  assert.equal(parseCoagentToolRequest('пример {"wesiTool":{"name":"tasks_list"}}'), null);
});

test('Co-Agent is skipped when Main policy disables collaboration', async () => {
  const value = prepared({coagent: {enabled: false, reason: 'single_persona_sufficient'}});
  const result = await runPersonaCoagent({prepared: value});
  assert.deepEqual(result, {ok: false, skipped: true, reason: 'single_persona_sufficient'});
});

test('Co-Agent raw model text is buffered and only structured result is returned', async () => {
  const events = [];
  let modelCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    emit: (event) => events.push(event),
    invokeModel: async () => {
      modelCalls += 1;
      return JSON.stringify({
        summary: 'UX требует упрощения.',
        findings: ['Слишком много действий на первом экране'],
        risks: ['Перегрузка интерфейса'],
        recommendation: 'Сократить первый экран.',
        artifacts: [],
      });
    },
    invokeTool: async () => { throw new Error('tool must not run'); },
  });
  assert.equal(modelCalls, 1);
  assert.equal(result.ok, true);
  assert.equal(result.result.persona, 'nirvana');
  assert.equal(result.result.finalOwner, 'lead');
  assert.equal(events.some((event) => event.type === 'delta'), false);
  assert.deepEqual(events.filter((event) => event.type === 'agent').map((event) => event.phase), ['handoff', 'start', 'result']);
});

test('Co-Agent can execute bounded read-only tool turn and gets verified result', async () => {
  const events = [];
  const modelInputs = [];
  let modelCalls = 0;
  let toolCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    emit: (event) => events.push(event),
    invokeModel: async ({input}) => {
      modelInputs.push(input);
      modelCalls += 1;
      if (modelCalls === 1) return '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
      return JSON.stringify({
        summary: 'Проверка завершена с реальными данными.',
        findings: ['Две задачи влияют на UX срок'],
        risks: [],
        recommendation: 'Учесть задачи в плане.',
        artifacts: ['tool:tasks_list'],
      });
    },
    invokeTool: async ({name, handoff}) => {
      toolCalls += 1;
      assert.equal(name, 'tasks_list');
      assert.equal(handoff.coagentPersona, 'nirvana');
      return {tool: name, verified: true, ok: true, result: {tasks: [{id: '1'}, {id: '2'}]}};
    },
  });
  assert.equal(result.ok, true);
  assert.equal(modelCalls, 2);
  assert.equal(toolCalls, 1);
  assert.equal(modelInputs[1].system.includes('WESI_AI_VERIFIED_COAGENT_TOOL_RESULTS'), true);
  assert.deepEqual(events.filter((event) => event.type === 'tool').map((event) => event.phase), ['start', 'result']);
});

test('Co-Agent cannot execute a tool outside scoped capabilities', async () => {
  let modelCalls = 0;
  let toolCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    invokeModel: async () => {
      modelCalls += 1;
      if (modelCalls === 1) return '{"wesiTool":{"name":"tasks_create","arguments":{"title":"x"}}}';
      return JSON.stringify({summary: 'Запись не выполнялась.', findings: [], risks: [], recommendation: 'Продолжить без изменения данных.', artifacts: []});
    },
    invokeTool: async () => { toolCalls += 1; return {}; },
  });
  assert.equal(result.ok, true);
  assert.equal(toolCalls, 0);
  assert.equal(result.toolResults[0].verified, true);
  assert.equal(result.toolResults[0].code, 'FORBIDDEN');
});

test('Co-Agent tool budget is fail-closed', async () => {
  let calls = 0;
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared({coagent: {...prepared().coagent, maxToolTurns: 1}}),
      invokeModel: async () => {
        calls += 1;
        return '{"wesiTool":{"name":"tasks_list","arguments":{"limit":1}}}';
      },
      invokeTool: async ({name}) => ({tool: name, verified: true, ok: true, result: {tasks: []}}),
    }),
    /WAI_COAGENT_TOOL_BUDGET_EXHAUSTED/,
  );
  assert.equal(calls, 2);
});

test('Co-Agent rejects hidden reasoning fields and malformed final response', async () => {
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared(),
      invokeModel: async () => JSON.stringify({summary: 'ok', reasoning: 'private'}),
      invokeTool: async () => ({}),
    }),
    /WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN/,
  );
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared(),
      invokeModel: async () => 'не json',
      invokeTool: async () => ({}),
    }),
    /WAI_COAGENT_RESULT_INVALID/,
  );
});
