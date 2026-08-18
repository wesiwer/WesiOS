// Агенты должны реально запускаться, а не только existовать в коде.
//
// Юнит-тесты рядом проверяют протокол по частям: спецификацию, ограничение
// прав, формат результата. Но между «протокол корректен» и «Зейн действительно
// собрал специалиста, тот отработал и вернул вывод» помещается вся сборка.
// Здесь прогоняется именно она — с моделью-заглушкой вместо провайдера.
import assert from 'node:assert/strict';
import test from 'node:test';
import {runDynamicSubagents} from './dynamic_subagent_orchestrator.mjs';
import {runPersonaCoagent} from './persona_coagent_orchestrator.mjs';
import {MAX_DYNAMIC_SUBAGENTS} from './dynamic_subagent.mjs';

const TOOL = {name: 'knowledge_search', parameters: {type: 'object', properties: {query: {type: 'string'}}}};

function prepared({tier = 'maximum', subagentsEnabled = true, coagentEnabled = true} = {}) {
  return {
    requestId: 'wai_stream_test',
    persona: 'zane',
    route: 'google/gemini-3.6-flash',
    systemParts: ['[PERSONA]\nЗейн'],
    history: [{author: 'user', text: 'Прошлое сообщение, которое агентам видеть незачем'}],
    message: 'Проверь безопасность формы входа и предложи улучшения',
    attachments: [],
    subagents: {
      enabled: subagentsEnabled,
      reason: subagentsEnabled ? 'bounded_dynamic_planner' : 'fast_tier_single_agent',
      context: [{kind: 'user_request', label: 'Запрос', text: 'Проверь безопасность формы входа'}],
      requestedCapabilities: ['knowledge_search'],
      grantedCapabilities: ['knowledge_search'],
      allowlistedCapabilities: ['knowledge_search'],
      destructiveCapabilities: [],
      allowedToolNames: ['knowledge_search'],
      toolDefinitions: [TOOL],
      maxAgents: tier === 'maximum' ? 3 : (tier === 'pro' ? 2 : 0),
      maxToolTurns: 2,
      maxTotalToolTurns: 6,
      maxOutputChars: 9000,
      maxWorkspaceEdits: 6,
      deadlineMs: 45000,
      workspaceFiles: [],
    },
    coagent: {
      enabled: coagentEnabled,
      reason: 'cross_domain_product',
      leadPersona: 'zane',
      coagentPersona: 'nirvana',
      task: 'Оцени понятность сообщений об ошибке',
      systemPrompt: '[PERSONA]\nНирвана',
      context: [{kind: 'user_request', label: 'Запрос', text: 'Проверь форму входа'}],
      requestedCapabilities: ['knowledge_search'],
      grantedCapabilities: ['knowledge_search'],
      allowlistedCapabilities: ['knowledge_search'],
      sideEffectCapabilities: [],
      allowedToolNames: ['knowledge_search'],
      toolDefinitions: [TOOL],
      maxToolTurns: 2,
      maxReviewRounds: 1,
      maxOutputChars: 6000,
      deadlineMs: 30000,
    },
  };
}

// Заглушка модели. seenInputs копит всё, что реально ушло бы провайдеру, —
// на этом проверяется изоляция контекста.
function stubModel({plan, decision = 'accept', seenInputs = []} = {}) {
  return async ({actor, phase, input}) => {
    seenInputs.push({actor, phase, input});
    if (phase === 'subagent-plan') return JSON.stringify(plan);
    if (phase === 'lead-review') return JSON.stringify({decision, revisionRequest: decision === 'revise' ? 'Уточни тексты' : ''});
    if (actor === 'coagent') {
      return JSON.stringify({summary: 'Нирвана: тексты ошибок смягчить', findings: ['«Ошибка 401» непонятна'], risks: [], recommendation: 'Переписать тексты'});
    }
    return JSON.stringify({
      summary: `Вывод специалиста ${actor}`,
      findings: ['Нет ограничения попыток'],
      risks: ['Подбор пароля'],
      recommendation: 'Добавить лимит попыток',
      workspaceEdits: [],
    });
  };
}
const stubTool = async ({name}) => ({ok: true, result: {tool: name, items: []}});

const TWO_SPECIALISTS = {
  subagents: [
    {role: 'Security Reviewer', task: 'Проверить форму входа на слабые проверки', requestedCapabilities: ['knowledge_search'], readablePaths: [], writablePaths: ['review.md']},
    {role: 'UX Reviewer', task: 'Оценить понятность ошибок', requestedCapabilities: [], readablePaths: [], writablePaths: []},
  ],
};

test('Зейн собирает специалистов, они отрабатывают и возвращают вывод', async () => {
  const events = [];
  const out = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: TWO_SPECIALISTS}),
    invokeTool: stubTool,
    emit: (ev) => events.push(ev),
    signal: null,
  });
  assert.equal(out.ok, true);
  assert.equal(out.skipped, false);
  assert.equal(out.results.length, 2);
  for (const result of out.results) {
    assert.equal(result.ok, true, `специалист ${result.spec?.role} не отработал: ${result.code}`);
    assert.ok(String(result.result.summary || '').length > 0);
  }
  assert.ok(events.some((ev) => String(ev.label || '').includes('Security Reviewer')),
    'пользователь не увидит, что появился специалист');
});

test('планировщик вправе не создавать никого', async () => {
  const out = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: {subagents: []}}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.equal(out.ok, true);
  assert.equal(out.skipped, true);
  assert.equal(out.reason, 'planner_selected_none');
});

test('на быстром уровне специалистов нет вовсе', async () => {
  const out = await runDynamicSubagents({
    prepared: prepared({tier: 'fast', subagentsEnabled: false}),
    invokeModel: stubModel({plan: TWO_SPECIALISTS}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.equal(out.skipped, true);
  assert.equal(out.reason, 'fast_tier_single_agent');
});

test('число специалистов ограничено сверху', async () => {
  const many = {subagents: Array.from({length: 6}, (_, i) => ({role: `Роль ${i}`, task: `Задача ${i}`, requestedCapabilities: [], readablePaths: [], writablePaths: []}))};
  const out = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: many}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.ok(out.results.length <= MAX_DYNAMIC_SUBAGENTS,
    `создано ${out.results.length} специалистов при пределе ${MAX_DYNAMIC_SUBAGENTS}`);
});

test('специалист не получает инструмент вне разрешённого списка', async () => {
  const greedy = {subagents: [{role: 'Жадный', task: 'Сделать всё', requestedCapabilities: ['knowledge_search', 'finance_transaction_delete'], readablePaths: [], writablePaths: []}]};
  const out = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: greedy}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  const granted = out.results[0]?.spec?.capabilities || [];
  assert.ok(!granted.includes('finance_transaction_delete'),
    'специалист получил разрушающий инструмент, которого ему не давали');
});

test('агентам не пересылается переписка пользователя', async () => {
  const seenInputs = [];
  await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: TWO_SPECIALISTS, seenInputs}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.ok(seenInputs.length > 0);
  for (const {actor, phase, input} of seenInputs) {
    assert.deepEqual(input.history, [],
      `${actor}/${phase} получил историю чата, хотя контекст должен быть минимальным`);
  }
});

test('Зейн передаёт слово Нирване и принимает её разбор', async () => {
  const events = [];
  const out = await runPersonaCoagent({
    prepared: prepared(),
    invokeModel: stubModel({plan: TWO_SPECIALISTS, decision: 'accept'}),
    invokeTool: stubTool,
    emit: (ev) => events.push(ev),
    signal: null,
  });
  assert.equal(out.ok, true);
  assert.equal(out.result.persona, 'nirvana');
  assert.ok(String(out.result.summary || '').length > 0);
  assert.ok(events.some((ev) => String(ev.label || '').includes('Нирвана')),
    'передача слова не видна пользователю');
});

test('Lead может отправить разбор Co-Agent на доработку', async () => {
  const out = await runPersonaCoagent({
    prepared: prepared(),
    invokeModel: stubModel({plan: TWO_SPECIALISTS, decision: 'revise'}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.equal(out.ok, true);
  assert.equal(out.result.persona, 'nirvana');
});

test('Co-Agent выключается, когда вторая персона не нужна', async () => {
  const out = await runPersonaCoagent({
    prepared: prepared({coagentEnabled: false}),
    invokeModel: stubModel({plan: TWO_SPECIALISTS}),
    invokeTool: stubTool,
    emit: () => {},
    signal: null,
  });
  assert.equal(out.ok, false);
  assert.equal(out.skipped, true);
});

test('без рабочей модели агент не запускается молча', async () => {
  await assert.rejects(
    () => runDynamicSubagents({prepared: prepared(), invokeModel: null, invokeTool: stubTool, emit: () => {}, signal: null}),
    /WAI_SUBAGENT_RUNTIME_INVALID/,
  );
  await assert.rejects(
    () => runPersonaCoagent({prepared: prepared(), invokeModel: null, invokeTool: stubTool, emit: () => {}, signal: null}),
    /WAI_COAGENT_RUNTIME_INVALID/,
  );
});

// Ход мыслей питается этими событиями. Если из них пропадёт поручение или
// фаза призыва, интерфейс не сможет показать, кого позвали и зачем, — а
// именно этого от него и ждут.
async function collectEvents() {
  const events = [];
  await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: stubModel({plan: TWO_SPECIALISTS}),
    invokeTool: stubTool,
    emit: (ev) => events.push(ev),
    signal: null,
  });
  return events;
}

test('призыв специалиста приходит отдельной фазой, а не как завершение', async () => {
  const events = await collectEvents();
  const planned = events.filter((ev) => ev.type === 'agent' && ev.phase === 'planned');
  assert.equal(planned.length, 2, 'событий призыва должно быть по одному на специалиста');
  for (const ev of planned) {
    assert.match(ev.label, /Зову специалиста/, `призыв подписан как «${ev.label}»`);
    assert.ok(ev.detail.length > 0, 'призыв без пояснения, зачем нужен специалист');
  }
});

test('событие агента несёт поручение', async () => {
  const events = await collectEvents();
  for (const ev of events.filter((x) => x.type === 'agent')) {
    assert.ok(String(ev.task || '').length > 0, `у события ${ev.phase} нет поручения`);
  }
});

test('завершение специалиста показывает его вывод, а не служебную фразу', async () => {
  const events = await collectEvents();
  const done = events.filter((ev) => ev.type === 'agent' && ev.phase === 'result');
  assert.equal(done.length, 2);
  for (const ev of done) {
    assert.match(ev.detail, /Вывод специалиста/, `завершение показывает «${ev.detail}»`);
  }
});

test('вызов инструмента подписан именем специалиста', async () => {
  const events = [];
  await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: async ({actor, phase}) => {
      if (phase === 'subagent-plan') return JSON.stringify({subagents: [TWO_SPECIALISTS.subagents[0]]});
      // Первый ход — запрос инструмента, второй — готовый результат.
      if (phase === 'tool-1') return JSON.stringify({wesiTool: {name: 'knowledge_search', arguments: {query: 'вход'}}});
      return JSON.stringify({summary: `Вывод ${actor}`, findings: [], risks: [], recommendation: '', workspaceEdits: []});
    },
    invokeTool: stubTool,
    emit: (ev) => events.push(ev),
    signal: null,
  });
  const toolEvents = events.filter((ev) => ev.type === 'tool');
  assert.ok(toolEvents.length >= 2, 'специалист не сходил в инструмент');
  for (const ev of toolEvents) {
    assert.equal(ev.agentName, 'Security Reviewer',
      'инструмент не подписан специалистом — в ходе мыслей не видно, кто его запустил');
  }
});
