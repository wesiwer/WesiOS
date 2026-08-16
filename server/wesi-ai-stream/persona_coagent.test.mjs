import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PERSONA_COAGENT_PROTOCOL,
  MAX_COAGENT_CONTEXT_ITEMS,
  MAX_COAGENT_CONTEXT_CHARS,
  createPersonaHandoff,
  validatePersonaHandoff,
  validatePersonaCoagentResult,
  scopeCoagentCapabilities,
  scopeCoagentContext,
  buildCoagentEvent,
} from './persona_coagent.mjs';

function handoff(overrides = {}) {
  return createPersonaHandoff({
    parentRequestId: 'req-12',
    leadPersona: 'Zane',
    coagentPersona: 'Nirvana',
    task: 'Проверь риски предложенного плана и верни краткие выводы.',
    context: [
      {kind: 'user_request', label: 'Запрос', text: 'Нужно проверить план.'},
      {kind: 'verified_tool_result', label: 'Задачи', text: '{"count":3}', verified: true},
    ],
    requestedCapabilities: ['tasks.read', 'finance.read'],
    grantedCapabilities: ['tasks.read', 'finance.read'],
    allowlistedCapabilities: ['tasks.read', 'finance.read'],
    ...overrides,
  });
}

test('creates a bounded Lead -> Co-Agent handoff with Lead owning final answer', () => {
  const value = handoff();
  assert.equal(value.protocol, PERSONA_COAGENT_PROTOCOL);
  assert.equal(value.depth, 1);
  assert.equal(value.policy.finalOwner, 'lead');
  assert.equal(value.policy.canSpawnAgents, false);
  assert.equal(value.policy.canDelegate, false);
  assert.equal(value.policy.canPerformDestructiveActions, false);
  assert.equal(value.policy.exposeChainOfThought, false);
  assert.equal(value.limits.maxReviewRounds, 1);
  assert.equal(value.limits.maxToolTurns, 2);
  assert.equal(validatePersonaHandoff(value), true);
});

test('scopes context and drops hidden/system/secret sources', () => {
  const huge = 'x'.repeat(MAX_COAGENT_CONTEXT_CHARS * 2);
  const value = scopeCoagentContext([
    {kind: 'system_prompt', text: 'never expose'},
    {kind: 'hidden_reasoning', text: 'private'},
    {kind: 'credential', text: 'token'},
    {kind: 'user_request', text: huge},
    ...Array.from({length: 20}, (_, index) => ({kind: 'project_context', text: `ctx-${index}`})),
  ]);
  assert.ok(value.length <= MAX_COAGENT_CONTEXT_ITEMS);
  assert.ok(value.reduce((sum, item) => sum + item.text.length, 0) <= MAX_COAGENT_CONTEXT_CHARS);
  assert.equal(value.some((item) => ['system_prompt', 'hidden_reasoning', 'credential'].includes(item.kind)), false);
});

test('unverified tool results cannot enter a validated handoff', () => {
  const value = handoff();
  value.context.push({kind: 'verified_tool_result', label: 'bad', text: '{}', verified: false});
  assert.throws(() => validatePersonaHandoff(value), /WAI_COAGENT_CONTEXT_UNVERIFIED/);
});

test('capabilities are strict intersection and side effects / recursive delegation are removed', () => {
  const value = scopeCoagentCapabilities({
    requested: ['tasks.read', 'tasks.write', 'agent.spawn', 'finance.read', 'unknown.read'],
    granted: ['tasks.read', 'tasks.write', 'agent.spawn', 'finance.read'],
    allowlisted: ['tasks.read', 'tasks.write', 'agent.spawn', 'finance.read'],
    sideEffectCapabilities: ['tasks.write'],
  });
  assert.deepEqual(value.sort(), ['finance.read', 'tasks.read']);
});

test('rejects recursion and same-persona delegation', () => {
  assert.throws(() => handoff({depth: 2}), /WAI_COAGENT_RECURSION_FORBIDDEN/);
  assert.throws(() => handoff({coagentPersona: 'zane'}), /WAI_COAGENT_PERSONA_INVALID/);
});

test('review and tool budgets are clamped to Stage 12 bounds', () => {
  const value = handoff({maxReviewRounds: 99, maxToolTurns: 99});
  assert.equal(value.limits.maxReviewRounds, 1);
  assert.equal(value.limits.maxToolTurns, 2);
});

test('validated Co-Agent result contains conclusions only and cannot carry hidden reasoning', () => {
  const value = handoff();
  const result = validatePersonaCoagentResult({
    summary: 'Есть два существенных риска.',
    findings: ['Риск сроков', 'Риск доступа'],
    risks: ['Высокая зависимость от внешнего API'],
    recommendation: 'Оставить fallback.',
    artifacts: ['tool:tasks.read:1'],
  }, value);
  assert.equal(result.finalOwner, 'lead');
  assert.equal(result.persona, 'Nirvana');
  assert.deepEqual(result.findings, ['Риск сроков', 'Риск доступа']);

  assert.throws(() => validatePersonaCoagentResult({
    summary: 'ok',
    reasoning: 'private chain',
  }, value), /WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN/);
  assert.throws(() => validatePersonaCoagentResult({
    summary: 'ok',
    meta: {chain_of_thought: 'private chain'},
  }, value), /WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN/);
});

test('observable Co-Agent event contains safe status only', () => {
  const value = handoff();
  const event = buildCoagentEvent(value, 'handoff', {
    label: 'Передано на проверку Nirvana',
    detail: 'Проверка рисков и ограничений.',
    reasoning: 'must be ignored',
  });
  assert.deepEqual(event, {
    type: 'agent',
    phase: 'handoff',
    role: 'coagent',
    name: 'Nirvana',
    lead: 'Zane',
    handoffId: 'req-12:coagent',
    label: 'Передано на проверку Nirvana',
    detail: 'Проверка рисков и ограничений.',
  });
});
