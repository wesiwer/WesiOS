import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const morning = require('./wesi_telegram_morning.js');

const aug18 = morning.localClock(Date.UTC(2026, 7, 18, 8, 0, 0), 0);
const aug19 = morning.localClock(Date.UTC(2026, 7, 19, 8, 0, 0), 0);
const aug20 = morning.localClock(Date.UTC(2026, 7, 20, 8, 0, 0), 0);
assert.equal(morning.speakerForDay(aug18.dayNumber), 'nirvana');
assert.equal(morning.speakerForDay(aug19.dayNumber), 'zane');
assert.equal(morning.speakerForDay(aug20.dayNumber), 'nirvana');

const berlinish = morning.localClock(Date.UTC(2026, 7, 19, 6, 0, 0), 120);
assert.equal(berlinish.hour, 8);
assert.equal(berlinish.dateKey, '2026-08-19');

const promptN = morning.generationPrompt('nirvana', {
  organizationName: 'WesiOS',
  dateKey: '2026-08-20',
  taskCount: 4,
  taskTitles: ['Закрыть релиз', 'Проверить задачи'],
  recentTexts: ['Вчерашнее сообщение для проверки неповторяемости.'],
});
assert.match(promptN, /общей большой цели/i);
assert.match(promptN, /командный дух/i);
assert.match(promptN, /великие дела/i);
assert.match(promptN, /не выдумывай конкретные достижения/i);
assert.match(promptN, /Нирвана/);
assert.match(promptN, /4 задач/);

const promptZ = morning.generationPrompt('zane', {
  organizationName: 'WesiOS',
  dateKey: '2026-08-21',
  taskCount: null,
  taskTitles: [],
  recentTexts: [],
});
assert.match(promptZ, /Зейн/);
assert.match(promptZ, /энергичный/i);
assert.match(promptZ, /проверить актуальные задачи/i);

const cleaned = morning.cleanGenerated('«' + 'Сегодня мы спокойно собираем сильный день. '.repeat(7) + '»');
assert.ok(cleaned.length >= morning.MIN_THREAD_CHARS);
assert.ok(cleaned.length <= morning.MAX_THREAD_CHARS);
assert.ok(!cleaned.startsWith('«'));

const photo = morning.photoFor('2026-08-20');
assert.ok(photo.startsWith('https://images.pexels.com/photos/'));
assert.equal(photo, morning.photoFor('2026-08-20'));

console.log('WESI_TELEGRAM_MORNING_AI_GENERATION_OK');
