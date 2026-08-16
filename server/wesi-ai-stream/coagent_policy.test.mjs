import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const policy = require('../pb_hooks/wesi_ai_coagent_policy.js');

function defs() {
  return [
    {name: 'tasks_list', wesiCapability: {risk: 'READ'}},
    {name: 'knowledge_search', wesiCapability: {risk: 'READ'}},
    {name: 'tasks_create', wesiCapability: {risk: 'WRITE'}},
    {name: 'github_pull_request_merge', wesiCapability: {risk: 'DESTRUCTIVE'}},
  ];
}

function evaluate(overrides = {}) {
  return policy.evaluate({
    leadPersona: 'zane',
    tier: 'pro',
    lobbyMode: 'smart',
    message: 'Почему падает сервер после деплоя?',
    projectContext: '',
    history: [],
    memory: {},
    attachments: [],
    toolDefinitions: defs(),
    ...overrides,
  });
}

test('single-specialty task stays with Lead when Co-Agent adds no value', () => {
  const result = evaluate();
  assert.equal(result.enabled, false);
  assert.equal(result.reason, 'single_persona_sufficient');
  assert.equal(result.coagentPersona, 'nirvana');
});

test('Zane delegates meaningful UX/UI work to Nirvana', () => {
  const result = evaluate({message: 'Сделай UI и UX нового dashboard: дизайн, типографика и анимации.'});
  assert.equal(result.enabled, true);
  assert.equal(result.coagentPersona, 'nirvana');
  assert.ok(['creative_review_needed', 'mixed_specializations'].includes(result.reason));
});

test('Nirvana delegates technical work to Zane', () => {
  const result = evaluate({
    leadPersona: 'nirvana',
    message: 'Спроектируй backend API, базу данных, security и CI build для приложения.',
  });
  assert.equal(result.enabled, true);
  assert.equal(result.coagentPersona, 'zane');
  assert.ok(['technical_review_needed', 'cross_domain_product'].includes(result.reason));
});

test('broad product work uses both personas even without keyword stuffing', () => {
  const result = evaluate({message: 'Сделай приложение для учёта тренировок.'});
  assert.equal(result.enabled, true);
  assert.equal(result.reason, 'cross_domain_product');
});

test('Fast requires a stronger cross-specialty signal unless task is broad', () => {
  const oneSignal = evaluate({tier: 'fast', message: 'Проверь UX.'});
  assert.equal(oneSignal.enabled, false);
  const strongSignal = evaluate({tier: 'fast', message: 'Проверь UX, UI, дизайн и анимации.'});
  assert.equal(strongSignal.enabled, true);
});

test('joint mode explicitly enables the Co-Agent', () => {
  const result = evaluate({lobbyMode: 'both', message: 'Коротко проверь идею.'});
  assert.equal(result.enabled, true);
  assert.equal(result.reason, 'joint_mode');
});

test('Co-Agent receives read-only tool scope and side effects stay outside', () => {
  const result = evaluate({message: 'Сделай приложение с хорошим UX.'});
  assert.deepEqual(result.allowedToolNames.sort(), ['knowledge_search', 'tasks_list']);
  assert.deepEqual(result.grantedCapabilities.sort(), ['knowledge_search', 'tasks_list']);
  assert.deepEqual(result.sideEffectCapabilities.sort(), ['github_pull_request_merge', 'tasks_create']);
});

test('Co-Agent context is scoped and excludes raw persona/system prompt', () => {
  const result = evaluate({
    message: 'Сделай приложение с хорошим UX.',
    projectContext: 'Проект WesiOS',
    history: [
      {author: 'user', text: 'предыдущий запрос'},
      {author: 'zane', text: 'предыдущий ответ'},
    ],
    memory: {shared: ['shared'], project: ['project'], nirvana: ['nirvana memory']},
    attachments: [{name: 'screen.png', mimeType: 'image/png', byteSize: 1000}],
  });
  assert.equal(result.context.some((item) => item.kind === 'user_request'), true);
  assert.equal(result.context.some((item) => item.kind === 'conversation_excerpt'), true);
  assert.equal(result.context.some((item) => item.kind === 'project_context'), true);
  assert.equal(result.context.some((item) => item.kind === 'memory_excerpt'), true);
  assert.equal(result.context.some((item) => item.kind === 'attachment_summary'), true);
  assert.equal(result.context.some((item) => ['system_prompt', 'hidden_reasoning', 'credential'].includes(item.kind)), false);
});
