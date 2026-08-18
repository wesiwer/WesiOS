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

const first = morning.variantFor('nirvana', '2026-08-20', '123');
const same = morning.variantFor('nirvana', '2026-08-20', '123');
assert.equal(first, same);
assert.ok(first.length > 80);
const photo = morning.photoFor('2026-08-20');
assert.ok(photo.startsWith('https://images.pexels.com/photos/'));
assert.equal(photo, morning.photoFor('2026-08-20'));

console.log('WESI_TELEGRAM_MORNING_ROTATION_OK');
