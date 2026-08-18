// Показанная мысль — обещание, а не отдельный текст рядом с ответом.
//
// «Мысли» и ответ формируются разными вызовами модели. Пока ответный вызов
// не видел показанных заметок, он сэмплировался заново: пользователь читал
// план «напишу генератор паролей», а получал сортировщик папок. Оба текста
// были осмысленными и никак не связанными.
import assert from 'node:assert/strict';
import test from 'node:test';
import {deliberationCommitment, relayPayload} from './gateway.mjs';

const prepared = {
  requestId: 'wai_stream_1',
  persona: 'zane',
  route: 'google/gemini-3.6-flash',
  systemParts: ['[PERSONA]\nЗейн'],
  history: [],
  message: 'Напиши любую программу',
  attachments: [],
};

const state = {
  complexity: 'normal',
  notes: [
    {kind: 'plan', title: 'Генератор паролей', text: 'Сделаю генератор и проверку надёжности пароля.'},
    {kind: 'decision', title: 'Python', text: 'Возьму Python и модуль secrets.'},
  ],
};

test('план попадает в системный промпт ответа', () => {
  const payload = relayPayload(prepared, [], 'final', true, state);
  const system = payload.input.system;
  assert.ok(system.includes('WESI_AI_PUBLIC_DELIBERATION_COMMITMENT'));
  assert.ok(system.includes('Генератор паролей'));
  assert.ok(system.includes('Сделаю генератор и проверку надёжности пароля.'));
});

test('ответу запрещено молча менять тему', () => {
  const system = relayPayload(prepared, [], 'final', true, state).input.system;
  assert.ok(system.includes('Финальный ответ обязан соответствовать им'));
  assert.ok(system.includes('Молча подменять тему нельзя'));
});

test('без размышления секция не появляется', () => {
  assert.equal(deliberationCommitment(null), '');
  assert.equal(deliberationCommitment({notes: []}), '');
  const system = relayPayload(prepared, [], '1', false).input.system;
  assert.ok(!system.includes('WESI_AI_PUBLIC_DELIBERATION_COMMITMENT'));
});

test('пустые заметки не создают пустую секцию', () => {
  assert.equal(deliberationCommitment({notes: [{title: '', text: ''}]}), '');
});

test('берутся последние десять шагов, а не вся история размышления', () => {
  const many = {notes: Array.from({length: 14}, (_, i) => ({title: `Шаг ${i}`, text: `Текст ${i}`}))};
  const text = deliberationCommitment(many);
  assert.ok(!text.includes('Шаг 3'));
  assert.ok(text.includes('Шаг 13'));
});

test('говорящий передаётся Relay', () => {
  assert.equal(relayPayload(prepared, [], 'final', true, state).input.persona, 'zane');
});

test('проверенные результаты инструментов не вытесняются планом', () => {
  const system = relayPayload(prepared, [{tool: 'finance_summary', ok: true}], 'final', true, state).input.system;
  assert.ok(system.includes('WESI_AI_VERIFIED_TOOL_RESULTS'));
  assert.ok(system.includes('WESI_AI_PUBLIC_DELIBERATION_COMMITMENT'));
});
