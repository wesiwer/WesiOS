import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_COAGENT_CAPABILITIES,
  MAX_COAGENT_CONTEXT_CHARS,
  MAX_COAGENT_CONTEXT_ITEMS,
  MAX_COAGENT_REVIEW_ROUNDS,
  buildPersonaCoAgentSystemPrompt,
  counterpartPersona,
  createPersonaCoAgentHandoff,
  intersectCapabilities,
  scopeCoAgentContext,
  validatePersonaCoAgentHandoff,
} from './persona-coagent.mjs';

test('counterpartPersona always selects the other canonical Persona', () => {
  assert.equal(counterpartPersona('Zane'), 'nirvana');
  assert.equal(counterpartPersona('nirvana'), 'zane');
  assert.equal(counterpartPersona('unknown'), null);
});

test('capabilities are strict intersection, deduplicated and bounded', () => {
  const requested = ['tasks.read', 'github.read', 'tasks.read', 'forbidden.write'];
  const available = ['tasks.read', 'github.read'];
  assert.deepEqual(intersectCapabilities(requested, available), ['tasks.read', 'github.read']);

  const many = Array.from({length: MAX_COAGENT_CAPABILITIES + 5}, (_, index) => `cap.${index}`);
  assert.equal(intersectCapabilities(many, many).length, MAX_COAGENT_CAPABILITIES);
});

test('context scope only admits approved typed facts and respects budgets', () => {
  const source = [
    {kind: 'user_request', content: 'Сделай проверку.'},
    {kind: 'secret_dump', content: 'never expose me'},
    ...Array.from({length: 20}, (_, index) => ({
      kind: 'project_fact',
      label: `fact-${index}`,
      content: 'x'.repeat(2000),
    })),
  ];
  const scoped = scopeCoAgentContext(source);
  assert.ok(scoped.length <= MAX_COAGENT_CONTEXT_ITEMS);
  assert.equal(scoped.some((item) => item.kind === 'secret_dump'), false);
  assert.ok(scoped.reduce((sum, item) => sum + item.content.length, 0) <= MAX_COAGENT_CONTEXT_CHARS);
});

test('typed handoff is fail-closed and cannot recursively delegate', () => {
  const handoff = createPersonaCoAgentHandoff({
    leadPersona: 'Zane',
    objective: 'Проверь архитектурные риски перед финальным ответом.',
    context: [
      {kind: 'user_request', content: 'Проверь архитектуру.'},
      {kind: 'verified_tool_result', content: '{"ok":true}', source: 'tasks.read'},
    ],
    requestedCapabilities: ['tasks.read', 'github.read', 'github.write'],
    availableCapabilities: ['tasks.read', 'github.read'],
  });

  assert.equal(handoff.lead, 'zane');
  assert.equal(handoff.coAgent, 'nirvana');
  assert.deepEqual(handoff.capabilities, ['tasks.read', 'github.read']);
  assert.equal(handoff.constraints.canDelegate, false);
  assert.equal(handoff.constraints.mayWriteFinal, false);
  assert.equal(handoff.constraints.verifiedToolResultsOnly, true);
  assert.equal(validatePersonaCoAgentHandoff(handoff, {availableCapabilities: ['tasks.read', 'github.read']}), true);

  const recursive = structuredClone(handoff);
  recursive.constraints.canDelegate = true;
  assert.equal(validatePersonaCoAgentHandoff(recursive, {availableCapabilities: ['tasks.read', 'github.read']}), false);

  const escalated = structuredClone(handoff);
  escalated.capabilities.push('github.write');
  assert.equal(validatePersonaCoAgentHandoff(escalated, {availableCapabilities: ['tasks.read', 'github.read']}), false);
});

test('review loop is explicitly bounded to one round in Stage 12', () => {
  assert.equal(MAX_COAGENT_REVIEW_ROUNDS, 1);
  const allowed = createPersonaCoAgentHandoff({
    leadPersona: 'Nirvana',
    objective: 'Review the lead draft.',
    reviewRound: 1,
  });
  assert.equal(allowed.reviewRound, 1);
  assert.throws(
    () => createPersonaCoAgentHandoff({leadPersona: 'Nirvana', objective: 'Again.', reviewRound: 2}),
    /WAI_COAGENT_REVIEW_LIMIT/,
  );
});

test('Co-Agent system prompt preserves role and no-final-answer constraints', () => {
  const handoff = createPersonaCoAgentHandoff({
    leadPersona: 'Zane',
    objective: 'Find conflicts.',
    context: [{kind: 'project_fact', content: 'A and B edit the same file.'}],
    requestedCapabilities: ['github.read'],
    availableCapabilities: ['github.read'],
  });
  const prompt = buildPersonaCoAgentSystemPrompt(handoff);
  assert.match(prompt, /WESI_PERSONA_COAGENT_HANDOFF/);
  assert.match(prompt, /не делегируй/i);
  assert.match(prompt, /не пиши финальный ответ/i);
  assert.match(prompt, /"coAgent":"nirvana"/);
});
