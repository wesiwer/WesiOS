// Длинный проход должен идти до конца задачи — и не дольше бюджета.
//
// Раньше цикл жёстко обрывался на четвёртом ходу: для «посчитай остаток»
// хватало, для «разберись и приведи в порядок» — нет, человеку приходилось
// после каждого шага писать «продолжай». Теперь проход идёт сам, но границы
// обязаны держать: без них сломанный инструмент или зациклившаяся модель
// будут крутиться, пока не кончатся деньги владельца.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  runBudget,
  relayPayload,
  MAX_RUN_STEPS_HARD_CAP,
  MAX_RUN_DEADLINE_MS_HARD_CAP,
  MAX_TOOL_TURNS,
} from './gateway.mjs';

const hooks = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../pb_hooks');
globalThis.__hooks = hooks;
const require = createRequire(import.meta.url);
const policy = require(path.join(hooks, 'wesi_ai_run_policy.js'));

const TOOLS = [{name: 'knowledge_search'}, {name: 'tasks_list'}];

test('быстрый уровень остаётся коротким, старшие получают длинный проход', () => {
  const fast = policy.evaluate({tier: 'fast', toolDefinitions: TOOLS});
  const pro = policy.evaluate({tier: 'pro', toolDefinitions: TOOLS});
  const max = policy.evaluate({tier: 'maximum', toolDefinitions: TOOLS});

  assert.equal(fast.autonomous, false, 'быстрый уровень не должен уходить в длинный проход');
  assert.ok(pro.maxSteps > fast.maxSteps);
  assert.ok(max.maxSteps > pro.maxSteps);
  assert.equal(pro.autonomous, true);
  assert.equal(max.autonomous, true);
});

test('без инструментов ходить некуда — остаётся один финальный шаг', () => {
  const none = policy.evaluate({tier: 'maximum', toolDefinitions: []});
  assert.equal(none.maxSteps, 1);
  assert.equal(none.autonomous, false);
  assert.equal(none.reason, 'no_tools_available');
});

test('у каждого уровня есть все три границы', () => {
  for (const tier of ['fast', 'pro', 'maximum']) {
    const evaluated = policy.evaluate({tier, toolDefinitions: TOOLS});
    assert.ok(evaluated.maxSteps > 0, `${tier}: нет предела шагов`);
    assert.ok(evaluated.deadlineMs > 0, `${tier}: нет предела времени`);
    assert.ok(evaluated.maxStalledSteps > 0, `${tier}: нет предела простоя`);
  }
});

test('неизвестный уровень получает самый осторожный бюджет', () => {
  const unknown = policy.evaluate({tier: 'сочинённый-уровень', toolDefinitions: TOOLS});
  assert.deepEqual(
    {steps: unknown.maxSteps, deadline: unknown.deadlineMs},
    {steps: policy.LIMITS.fast.steps, deadline: policy.LIMITS.fast.deadlineMs},
  );
});

test('шлюз не пускает бюджет выше жёсткого потолка', () => {
  // Ошибка в политике не должна превращаться в бесконечный проход.
  const budget = runBudget({run: {maxSteps: 100000, deadlineMs: 99 * 60 * 60000, autonomous: true}});
  assert.equal(budget.maxSteps, MAX_RUN_STEPS_HARD_CAP);
  assert.equal(budget.deadlineMs, MAX_RUN_DEADLINE_MS_HARD_CAP);
});

test('без политики шлюз работает по-старому, а не без границ', () => {
  const budget = runBudget({});
  assert.equal(budget.maxSteps, MAX_TOOL_TURNS);
  assert.equal(budget.autonomous, false);
  assert.ok(budget.deadlineMs > 0);
});

test('мусор в политике не отключает границы', () => {
  for (const broken of [
    {run: {maxSteps: -5, deadlineMs: 0, maxStalledSteps: -1}},
    {run: {maxSteps: 'много', deadlineMs: null, maxStalledSteps: NaN}},
    {run: null},
  ]) {
    const budget = runBudget(broken);
    assert.ok(budget.maxSteps > 0 && budget.maxSteps <= MAX_RUN_STEPS_HARD_CAP);
    assert.ok(budget.deadlineMs > 0 && budget.deadlineMs <= MAX_RUN_DEADLINE_MS_HARD_CAP);
    assert.ok(budget.maxStalledSteps > 0);
  }
});

const preparedFor = (run) => ({
  requestId: 'wai_stream_run',
  persona: 'zane',
  route: 'google/gemini-3.6-flash',
  systemParts: ['[PERSONA]\nЗейн'],
  history: [],
  message: 'Разберись с формой входа',
  attachments: [],
  run,
});

test('в длинном проходе персоне сказано не ждать «продолжай»', () => {
  const system = relayPayload(
    preparedFor(policy.evaluate({tier: 'maximum', toolDefinitions: TOOLS})),
    [], '1', false,
  ).input.system;
  assert.match(system, /WESI_AI_LONG_RUN/);
  assert.match(system, /продолжай/i);
  assert.match(system, /до 40 шагов/);
});

test('разрушающие действия не освобождаются длинным проходом', () => {
  const system = relayPayload(
    preparedFor(policy.evaluate({tier: 'maximum', toolDefinitions: TOOLS})),
    [], '1', false,
  ).input.system;
  assert.match(system, /Разрушающие действия/);
});

test('на коротком уровне указания про длинный проход нет', () => {
  const system = relayPayload(
    preparedFor(policy.evaluate({tier: 'fast', toolDefinitions: TOOLS})),
    [], '1', false,
  ).input.system;
  assert.doesNotMatch(system, /WESI_AI_LONG_RUN/);
});

test('финальный ход требует честно назвать несделанное', () => {
  const system = relayPayload(
    preparedFor(policy.evaluate({tier: 'maximum', toolDefinitions: TOOLS})),
    [], 'final', true,
  ).input.system;
  assert.match(system, /WESI_AI_FINAL_RESPONSE/);
  assert.match(system, /не выдавай половину за целое/);
  assert.doesNotMatch(system, /WESI_AI_LONG_RUN/);
});
