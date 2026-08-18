import assert from 'node:assert/strict';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const photos = require('./wesi_telegram_morning_photos.js');

assert.ok(photos.PHOTO_IDS.length >= 60);
assert.equal(photos.PHOTO_IDS.length, new Set(photos.PHOTO_IDS).size);
assert.equal(photos.PHOTOS.length, photos.PHOTO_IDS.length);
for (const url of photos.PHOTOS) {
  assert.match(url, /^https:\/\/images\.pexels\.com\/photos\/\d+\/pexels-photo-\d+\.jpeg\?/);
}
console.log(`WESI_TELEGRAM_MORNING_PHOTOS_OK count=${photos.PHOTOS.length}`);
