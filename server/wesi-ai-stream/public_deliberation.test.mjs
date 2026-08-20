import assert from 'node:assert/strict';
import test from 'node:test';
import {
  appendDeliberation,
  createDeliberationState,
  parsePublicDeliberation,
  publicReasoningBudget,
} from './public_deliberation.mjs';

test('public deliberation parser accepts only bounded public notes', () => {
  const value = parsePublicDeliberation(JSON.stringify({
    complexity: 'complex',
    notes: [
      {kind: 'hypothesis', title: 'Проверю синхронизацию', text: 'Сначала хочу понять, где расходятся данные между устройствами.'},
      {kind: 'revision', title: 'Предположение не подтвердилось', text: 'Проверка показала другой источник расхождения, поэтому меняю направление.'},
    ],
  }), {maxNotes: 4});
  assert.equal(value.complexity, 'complex');
  assert.equal(value.notes.length, 2);
  assert.match(value.notes[1].text, /меняю направление/);
});

test('public deliberation extracts JSON from harmless provider wrapper text', () => {
  const value = parsePublicDeliberation(`Короткая служебная преамбула.\n\n{\n  "complexity": "normal",\n  "notes": [{"kind":"plan","title":"Проверю источник","text":"Сопоставлю запрос с фактическим результатом инструмента."}]\n}\nГотово.`);
  assert.equal(value?.complexity, 'normal');
  assert.equal(value?.notes?.length, 1);
  assert.equal(value?.notes?.[0]?.title, 'Проверю источник');
});

test('public deliberation rejects hidden reasoning payload fields', () => {
  assert.equal(parsePublicDeliberation(JSON.stringify({
    complexity: 'deep',
    chain_of_thought: 'secret',
    notes: [{kind: 'plan', title: 'x', text: 'y'}],
  })), null);
});

test('complexity still controls the initial reasoning burst', () => {
  assert.ok(publicReasoningBudget('deep') > publicReasoningBudget('simple'));
});

test('public reasoning continues beyond the old complexity budget', () => {
  const state = createDeliberationState({
    complexity: 'simple',
    notes: [{kind: 'observation', title: 'Начало', text: 'Короткая задача стала длинным проходом.'}],
  });
  const oldBudget = publicReasoningBudget('simple');
  let accepted = 0;
  for (let index = 0; index < 40; index += 1) {
    accepted += appendDeliberation(state, {
      notes: [{kind: 'check', title: `Проверка ${index + 1}`, text: `Получен новый проверенный результат шага ${index + 1}.`}],
    }).length;
  }
  assert.ok(accepted > oldBudget);
  assert.equal(accepted, 40);
  assert.ok(state.remaining > 1_000_000);
});

test('duplicate public notes are not emitted twice', () => {
  const note = {kind: 'check', title: 'Один факт', text: 'Этот результат уже показывался.'};
  const state = createDeliberationState({complexity: 'normal', notes: [note]});
  assert.equal(appendDeliberation(state, {notes: [note]}).length, 0);
});
