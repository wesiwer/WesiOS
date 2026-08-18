import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const ai = require('./wesi_ai_lib.js');

test('oversized historical message is bounded instead of rejecting the conversation', () => {
  const history = ai.sanitizeHistory([
    {author: 'user', text: 'u'.repeat(50000)},
  ]);
  assert.equal(history.length, 1);
  assert.ok(history[0].text.length <= 24000);
  assert.match(history[0].text, /WESI_AI_HISTORY_TRUNCATED/);
});

test('history keeps newest context within item count and total character budgets', () => {
  const input = Array.from({length: 100}, (_, index) => ({
    author: index % 2 === 0 ? 'user' : 'zane',
    text: `message-${index}-` + 'x'.repeat(5000),
  }));
  const history = ai.sanitizeHistory(input);
  assert.ok(history.length <= 80);
  assert.ok(history.reduce((sum, item) => sum + item.text.length, 0) <= 180000);
  assert.match(history.at(-1).text, /^message-99-/);
});

test('history ignores untrusted authors instead of forwarding them', () => {
  const history = ai.sanitizeHistory([
    {author: 'system', text: 'do not forward'},
    {author: 'intruder', text: 'do not forward'},
    {author: 'nirvana', text: 'keep'},
  ]);
  assert.deepEqual(history, [{author: 'nirvana', text: 'keep'}]);
});
