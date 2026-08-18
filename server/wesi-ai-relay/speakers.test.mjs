import assert from 'node:assert/strict';
import test from 'node:test';
import {speakerTurns, mergeAdjacent, geminiContents, openAiHistory} from './speakers.mjs';

const lobby = {
  persona: 'nirvana',
  history: [
    {author: 'user', text: 'Придумайте название'},
    {author: 'zane', text: 'Назови это Sharp.'},
  ],
};

test('реплика другого участника не выдаётся за собственную речь', () => {
  const turns = speakerTurns(lobby);
  assert.equal(turns.length, 2);
  assert.equal(turns[1].role, 'user');
  assert.ok(turns[1].text.startsWith('[Зейн]:'));
});

test('собственная прошлая реплика остаётся речью модели', () => {
  const turns = speakerTurns({persona: 'nirvana', history: [{author: 'nirvana', text: 'Я предлагаю Soft.'}]});
  assert.equal(turns[0].role, 'model');
  assert.equal(turns[0].text, 'Я предлагаю Soft.');
});

test('результат инструмента — входящие данные, а не речь модели', () => {
  const turns = speakerTurns({persona: 'zane', history: [{author: 'tool', text: '{"currentBalance":500}'}]});
  assert.equal(turns[0].role, 'user');
  assert.ok(turns[0].text.startsWith('[Результат инструмента]'));
});

test('в обычном чате без персоны прошлая речь модели не переклеивается', () => {
  const turns = speakerTurns({history: [{author: 'zane', text: 'Ответ'}, {author: 'nirvana', text: 'Другой'}]});
  assert.deepEqual(turns.map((t) => t.role), ['model', 'model']);
});

test('подряд идущие роли склеиваются', () => {
  const merged = mergeAdjacent([
    {role: 'user', text: 'раз'},
    {role: 'user', text: 'два'},
    {role: 'model', text: 'три'},
  ]);
  assert.equal(merged.length, 2);
  assert.equal(merged[0].text, 'раз\n\nдва');
});

test('пустые реплики выбрасываются', () => {
  assert.equal(speakerTurns({persona: 'zane', history: [{author: 'user', text: '   '}, {author: 'zane', text: ''}]}).length, 0);
});

test('Gemini получает contents с сохранённой личностью', () => {
  const contents = geminiContents(lobby);
  assert.equal(contents[contents.length - 1].role, 'user');
  assert.ok(contents[contents.length - 1].parts[0].text.includes('[Зейн]:'));
});

test('OpenAI-путь подчиняется тому же правилу', () => {
  const messages = openAiHistory(lobby);
  assert.equal(messages[messages.length - 1].role, 'user');
  assert.ok(messages[messages.length - 1].content.includes('[Зейн]:'));
});

test('история без персон не ломается', () => {
  assert.deepEqual(speakerTurns({}), []);
  assert.deepEqual(speakerTurns({history: null}), []);
});
