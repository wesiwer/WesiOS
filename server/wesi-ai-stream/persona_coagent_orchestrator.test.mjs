import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseCoagentToolRequest,
  parseLeadReviewResponse,
  runPersonaCoagent,
} from './persona_coagent_orchestrator.mjs';

function prepared(overrides = {}) {
  const base = {
    requestId: 'wai_stage12_test',
    persona: 'zane',
    tier: 'pro',
    route: 'wesi/pro',
    message: 'Сделай приложение с хорошим UX.',
    systemParts: ['Ты Зейн, Technical / Analytical Persona Agent Wesi AI.'],
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
  };
  return {...base, ...overrides};
}

function coagentResult(overrides = {}) {
  return JSON.stringify({
    summary: 'UX требует упрощения.',
    findings: ['Слишком много действий на первом экране'],
    risks: ['Перегрузка интерфейса'],
    recommendation: 'Сократить первый экран.',
    artifacts: [],
    ...overrides,
  });
}

test('Co-Agent tool parser accepts exact service envelope only', () => {
  assert.deepEqual(
    parseCoagentToolRequest('{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}'),
    {name: 'tasks_list', arguments: {limit: 2}},
  );
  assert.equal(parseCoagentToolRequest('Обычный текст'), null);
  assert.equal(parseCoagentToolRequest('пример {"wesiTool":{"name":"tasks_list"}}'), null);
});

test('Lead review parser is typed and fail-closed', () => {
  const value = prepared();
  const handoff = {
    protocol: 'wesi.persona-coagent.v1',
    kind: 'persona_handoff',
    handoffId: 'h1',
    parentRequestId: value.requestId,
    depth: 1,
    leadPersona: 'zane',
    coagentPersona: 'nirvana',
    task: 'Проверь UX/UI.',
    context: [],
    capabilities: [],
    limits: {maxReviewRounds: 1, maxToolTurns: 0, maxContextItems: 8, maxContextChars: 12000},
    policy: {finalOwner: 'lead', canSpawnAgents: false, canDelegate: false, canPerformDestructiveActions: false, exposeChainOfThought: false},
    outputSchema: {summary: 'string', findings: 'string[]', risks: 'string[]', recommendation: 'string', artifacts: 'string[]'},
  };
  assert.equal(parseLeadReviewResponse('{"decision":"accept"}', handoff).decision, 'accept');
  assert.equal(parseLeadReviewResponse('{"decision":"revise","revisionRequest":"Уточни навигацию"}', handoff).decision, 'revise');
  assert.throws(() => parseLeadReviewResponse('{"decision":"maybe"}', handoff), /WAI_COAGENT_REVIEW_INVALID/);
  assert.throws(() => parseLeadReviewResponse('{"decision":"accept","reasoning":"private"}', handoff), /WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN/);
});

test('Co-Agent is skipped when Main policy disables collaboration', async () => {
  const value = prepared({coagent: {enabled: false, reason: 'single_persona_sufficient'}});
  const result = await runPersonaCoagent({prepared: value});
  assert.deepEqual(result, {ok: false, skipped: true, reason: 'single_persona_sufficient'});
});

test('Co-Agent raw model text is buffered, Lead reviews it, and only structured result is returned', async () => {
  const events = [];
  let modelCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    emit: (event) => events.push(event),
    invokeModel: async ({actor}) => {
      modelCalls += 1;
      return actor === 'lead' ? '{"decision":"accept"}' : coagentResult();
    },
    invokeTool: async () => { throw new Error('tool must not run'); },
  });
  assert.equal(modelCalls, 2);
  assert.equal(result.ok, true);
  assert.equal(result.review.decision, 'accept');
  assert.equal(result.result.persona, 'nirvana');
  assert.equal(result.result.finalOwner, 'lead');
  assert.equal(events.some((event) => event.type === 'delta'), false);
  assert.deepEqual(
    events.filter((event) => event.type === 'agent').map((event) => event.phase),
    ['handoff', 'start', 'result', 'review'],
  );
  const workLabels = events.filter((event) => event.type === 'activity').map((event) => event.label);
  assert.deepEqual(workLabels, [
    'Зейн → Нирвана',
    'Нирвана · Co-Agent проверка',
    'Нирвана → Зейн',
    'Зейн · проверка Co-Agent результата',
    'Зейн · результат принят',
  ]);
});

test('Co-Agent can execute bounded read-only tool turn and Lead reviews verified result', async () => {
  const events = [];
  const modelInputs = [];
  let coagentCalls = 0;
  let leadCalls = 0;
  let toolCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    emit: (event) => events.push(event),
    invokeModel: async ({actor, input}) => {
      modelInputs.push({actor, input});
      if (actor === 'lead') {
        leadCalls += 1;
        return '{"decision":"accept"}';
      }
      coagentCalls += 1;
      if (coagentCalls === 1) return '{"wesiTool":{"name":"tasks_list","arguments":{"limit":2}}}';
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
  assert.equal(coagentCalls, 2);
  assert.equal(leadCalls, 1);
  assert.equal(toolCalls, 1);
  const secondCoagent = modelInputs.filter((item) => item.actor === 'coagent')[1];
  assert.equal(secondCoagent.input.system.includes('WESI_AI_VERIFIED_COAGENT_TOOL_RESULTS'), true);
  assert.deepEqual(events.filter((event) => event.type === 'tool').map((event) => event.phase), ['start', 'result']);
});

test('Co-Agent cannot execute a tool outside scoped capabilities', async () => {
  let coagentCalls = 0;
  let toolCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    invokeModel: async ({actor}) => {
      if (actor === 'lead') return '{"decision":"accept"}';
      coagentCalls += 1;
      if (coagentCalls === 1) return '{"wesiTool":{"name":"tasks_create","arguments":{"title":"x"}}}';
      return JSON.stringify({summary: 'Запись не выполнялась.', findings: [], risks: [], recommendation: 'Продолжить без изменения данных.', artifacts: []});
    },
    invokeTool: async () => { toolCalls += 1; return {}; },
  });
  assert.equal(result.ok, true);
  assert.equal(toolCalls, 0);
  assert.equal(result.toolResults[0].verified, true);
  assert.equal(result.toolResults[0].code, 'FORBIDDEN');
});

test('Lead can request exactly one revision round and revision cannot use tools', async () => {
  const events = [];
  const calls = [];
  let coagentCalls = 0;
  const result = await runPersonaCoagent({
    prepared: prepared(),
    emit: (event) => events.push(event),
    invokeModel: async ({actor, phase, input}) => {
      calls.push({actor, phase, input});
      if (actor === 'lead') {
        return '{"decision":"revise","revisionRequest":"Уточни навигацию и первый экран"}';
      }
      coagentCalls += 1;
      if (coagentCalls === 1) return coagentResult();
      return coagentResult({
        summary: 'UX уточнён после review.',
        recommendation: 'Сделать навигацию в два уровня.',
        reviewRound: 1,
      });
    },
    invokeTool: async () => { throw new Error('revision must not use tools'); },
  });
  assert.equal(calls.length, 3);
  assert.deepEqual(calls.map((call) => `${call.actor}:${call.phase}`), [
    'coagent:tool-1',
    'lead:lead-review',
    'coagent:revision',
  ]);
  assert.equal(result.review.decision, 'revise');
  assert.equal(result.result.reviewRound, 1);
  assert.equal(result.result.summary, 'UX уточнён после review.');
  assert.equal(result.previousResult.summary, 'UX требует упрощения.');
  const revision = calls[2];
  assert.equal(revision.input.system.includes('WESI_AI_COAGENT_FINAL_ONLY'), true);
  assert.equal(revision.input.system.includes('WESI_AI_COAGENT_TOOL_PROTOCOL'), false);
  assert.equal(revision.input.system.includes('Уточни навигацию и первый экран'), true);
  assert.equal(events.filter((event) => event.type === 'agent' && event.phase === 'revision').length, 1);
  assert.equal(events.filter((event) => event.type === 'agent' && event.phase === 'review').length, 1);
});

test('Co-Agent tool budget is fail-closed before Lead review', async () => {
  let calls = 0;
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared({coagent: {...prepared().coagent, maxToolTurns: 1}}),
      invokeModel: async ({actor}) => {
        assert.equal(actor, 'coagent');
        calls += 1;
        return '{"wesiTool":{"name":"tasks_list","arguments":{"limit":1}}}';
      },
      invokeTool: async ({name}) => ({tool: name, verified: true, ok: true, result: {tasks: []}}),
    }),
    /WAI_COAGENT_TOOL_BUDGET_EXHAUSTED/,
  );
  assert.equal(calls, 2);
});

test('Co-Agent rejects hidden reasoning fields and malformed final response before Lead review', async () => {
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared(),
      invokeModel: async ({actor}) => {
        assert.equal(actor, 'coagent');
        return JSON.stringify({summary: 'ok', reasoning: 'private'});
      },
      invokeTool: async () => ({}),
    }),
    /WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN/,
  );
  await assert.rejects(
    runPersonaCoagent({
      prepared: prepared(),
      invokeModel: async ({actor}) => {
        assert.equal(actor, 'coagent');
        return 'не json';
      },
      invokeTool: async () => ({}),
    }),
    /WAI_COAGENT_RESULT_INVALID/,
  );
});
