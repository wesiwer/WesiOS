import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const turn = require('./wesi_ai_lobby_turn.js');
const violation = turn._test.identityViolation;

test('accepts ordinary self-consistent replies', () => {
  assert.equal(violation('zane', 'Проверил логи. Проблема в stream prepare.'), '');
  assert.equal(violation('nirvana', 'Давай сделаем стих менее прямолинейным и образнее.'), '');
});

test('rejects response labeled as the other persona', () => {
  assert.equal(violation('zane', 'Нирвана: давай сделаем мягче.'), 'other_label');
  assert.equal(violation('nirvana', 'Зейн: тут ошибка в сервере.'), 'other_label');
});

test('rejects claiming the other identity', () => {
  assert.equal(violation('zane', 'Я Нирвана, сейчас отвечу.'), 'other_identity');
  assert.equal(violation('nirvana', 'Я Зейн, слушаю.'), 'other_identity');
});

test('rejects summoning self - screenshot regression', () => {
  assert.equal(
    violation('zane', 'Секунду, сейчас позову Зейна. Зейн! Тут тебя спрашивают.'),
    'self_summon',
  );
  assert.equal(
    violation('nirvana', 'Сейчас позову Нирвану, подожди.'),
    'self_summon',
  );
});

test('rejects speaking about self in third person - poem screenshot regression', () => {
  assert.equal(
    violation('nirvana', 'Нирвана бы рыдала над долей такой, а я говорю: расслабься.'),
    'self_third_person',
  );
  assert.equal(
    violation('zane', 'Зейн бы сказал иначе, а я сейчас отвечу.'),
    'self_third_person',
  );
});

test('persona boundary explicitly forbids imitation', () => {
  const zane = turn._test.personaIdentity('zane').boundary;
  const nirvana = turn._test.personaIdentity('nirvana').boundary;
  assert.match(zane, /Нирвана — отдельный участник/);
  assert.match(nirvana, /Зейн — отдельный участник/);
  assert.match(zane, /маршрутизатор Lobby/);
  assert.match(nirvana, /маршрутизатор Lobby/);
});
