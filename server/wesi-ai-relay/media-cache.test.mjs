import test from 'node:test';
import assert from 'node:assert/strict';
import {putMedia, takeMedia, cacheStats, clearMediaCacheForTests} from './media-cache.mjs';

test('Relay media artifact is one-time and byte-accurate', () => {
  clearMediaCacheForTests();
  const raw = Buffer.from('private-media');
  const stored = putMedia({
    kind: 'image',
    mimeType: 'image/png',
    data: raw.toString('base64'),
    byteSize: raw.length,
  });
  assert.equal(stored.ok, true);
  assert.match(stored.artifactId, /^[A-Za-z0-9_-]+$/);
  assert.equal(cacheStats().items, 1);

  const first = takeMedia(stored.artifactId);
  assert.ok(first);
  assert.equal(first.mimeType, 'image/png');
  assert.equal(first.bytes.toString(), 'private-media');
  assert.equal(takeMedia(stored.artifactId), null);
  assert.equal(cacheStats().items, 0);
});

test('Relay media cache rejects declared size mismatch', () => {
  clearMediaCacheForTests();
  const stored = putMedia({
    kind: 'music',
    mimeType: 'audio/mpeg',
    data: Buffer.from('audio').toString('base64'),
    byteSize: 999,
  });
  assert.equal(stored.ok, false);
  assert.equal(stored.code, 'WAI_PROVIDER_BAD_MEDIA');
});

test('invalid artifact ids cannot access cache', () => {
  clearMediaCacheForTests();
  assert.equal(takeMedia('../secret'), null);
  assert.equal(takeMedia(''), null);
});
