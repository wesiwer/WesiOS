import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const router = require('./wesi_ai_lobby_router.js');

const route = router._test.deterministicRoute;

test('creative request routes to Nirvana', () => {
  assert.deepEqual(route('напиши стих', []), ['nirvana']);
  assert.deepEqual(route('придумай обложку для трека', []), ['nirvana']);
});

test('technical and finance requests route to Zane', () => {
  assert.deepEqual(route('почему упал сервер и где ошибка в логе?', []), ['zane']);
  assert.deepEqual(route('сколько денег у Wesi Inc?', []), ['zane']);
});

test('pronoun handoff calls the opposite persona instead of impersonating it', () => {
  assert.deepEqual(
    route('позови его', [{author: 'zane', text: 'Я здесь.'}]),
    ['zane', 'nirvana'],
  );
  assert.deepEqual(
    route('позови её', [{author: 'nirvana', text: 'Я здесь.'}]),
    ['nirvana', 'zane'],
  );
});

test('explicit handoff keeps caller then target when both are known', () => {
  assert.deepEqual(
    route('Зейн, позови Нирвану', [{author: 'zane', text: 'Слушаю.'}]),
    ['zane', 'nirvana'],
  );
});

test('explicit persona mention wins over generic creative routing', () => {
  assert.deepEqual(route('Зейн, напиши короткий стих', []), ['zane']);
  assert.deepEqual(route('Нирвана, проверь этот текст', []), ['nirvana']);
});

test('ambiguous request is left to model router', () => {
  assert.equal(route('что думаешь?', []), null);
});
