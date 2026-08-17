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

test('public deliberation rejects hidden reasoning payload fields', () => {
  assert.equal(parsePublicDeliberation(JSON.stringify({
    complexity: 'deep',
    chain_of_thought: 'secret',
    notes: [{kind: 'plan', title: 'x', text: 'y'}],
  })), null);
});

test('reasoning budget grows with task complexity and is enforced', () => {
  assert.ok(publicReasoningBudget('deep') > publicReasoningBudget('simple'));
  const state = createDeliberationState({
    complexity: 'simple',
    notes: [{kind: 'observation', title: 'Начало', text: 'Короткая задача.'}],
  });
  const added = appendDeliberation(state, {
    notes: [
      {kind: 'decision', title: 'Итог', text: 'Достаточно прямого ответа.'},
      {kind: 'decision', title: 'Лишнее', text: 'Не должно войти.'},
    ],
  });
  assert.equal(added.length, 1);
  assert.equal(state.remaining, 0);
});
