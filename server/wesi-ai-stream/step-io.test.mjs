// Шаг должен быть проверяемым, а не только наблюдаемым.
//
// Сводки «Инструмент · finance_summary» хватает, чтобы следить за ходом. Но
// в длинном проходе шагов два десятка, и без аргументов вызова и ответа
// инструмента человеку остаётся верить им на слово.
import assert from 'node:assert/strict';
import test from 'node:test';
import {stepIo, MAX_STEP_IO_CHARS} from './step_io.mjs';

test('аргументы и ответ едут вместе с шагом', () => {
  const io = stepIo(
    {name: 'finance_summary', arguments: {organizationId: 'org_wesi_inc'}},
    {ok: true, result: {currentBalance: 700}},
  );
  assert.match(io.input, /org_wesi_inc/);
  assert.match(io.output, /currentBalance/);
  assert.match(io.output, /700/);
});

test('у отказа показывается причина, а не пустота', () => {
  const io = stepIo(
    {name: 'tasks_create', arguments: {title: 'Задача'}},
    {ok: false, code: 'FORBIDDEN', message: 'Нет доступа к модулю задач'},
  );
  // result отсутствует — показываем сам ответ, иначе человек увидит только,
  // что шаг не удался, но не поймёт почему.
  assert.match(io.output, /FORBIDDEN/);
  assert.match(io.output, /Нет доступа/);
});

test('длинный ответ обрезается, а не уходит целиком', () => {
  const huge = {rows: Array.from({length: 5000}, (_, i) => `строка ${i}`)};
  const io = stepIo({name: 'x', arguments: {}}, {ok: true, result: huge});
  assert.ok(io.output.length <= MAX_STEP_IO_CHARS,
    `вывод ${io.output.length} символов при пределе ${MAX_STEP_IO_CHARS}`);
});

test('пустые аргументы не создают пустых блоков', () => {
  const io = stepIo({name: 'tasks_list', arguments: undefined}, {ok: true, result: null});
  assert.equal('input' in io, false);
  assert.equal('output' in io, false);
});

test('циклическая ссылка не роняет проход', () => {
  const cyclic = {name: 'loop'};
  cyclic.self = cyclic;
  const io = stepIo({name: 'x', arguments: cyclic}, {ok: true, result: cyclic});
  assert.equal(io.input, undefined);
  assert.equal(io.output, undefined);
});
