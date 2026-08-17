import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const handoff = require('./wesi_ai_remote_media_handoff_lib.js');

test('remote media file metadata stays bounded and chunked', () => {
  const meta = handoff.normalizeFileMeta({
    name: '../voice.wav',
    mimeType: 'audio/wav; charset=binary',
    byteSize: handoff.CHUNK_BYTES + 7,
    sha256: 'a'.repeat(64),
  });
  assert.equal(meta.name, '.._voice.wav');
  assert.equal(meta.mimeType, 'audio/wav');
  assert.equal(meta.chunkCount, 2);
  assert.equal(handoff.expectedChunkBytes(meta, 0), handoff.CHUNK_BYTES);
  assert.equal(handoff.expectedChunkBytes(meta, 1), 7);
});

test('remote media rejects unsafe MIME, size and digest', () => {
  assert.throws(
    () => handoff.normalizeFileMeta({
      name: 'payload.exe',
      mimeType: 'application/x-msdownload',
      byteSize: 4,
      sha256: 'a'.repeat(64),
    }),
    /WRM_MIME_FORBIDDEN/,
  );
  assert.throws(
    () => handoff.normalizeFileMeta({
      name: 'x.wav',
      mimeType: 'audio/wav',
      byteSize: handoff.MAX_FILE_BYTES + 1,
      sha256: 'a'.repeat(64),
    }),
    /WRM_FILE_SIZE_INVALID/,
  );
  assert.throws(
    () => handoff.normalizeFileMeta({
      name: 'x.wav',
      mimeType: 'audio/wav',
      byteSize: 4,
      sha256: 'not-a-digest',
    }),
    /WRM_BAD_SHA256/,
  );
});

test('worker binding requires a real assignment and becomes sticky', () => {
  const workerA = 'a'.repeat(32);
  const workerB = 'b'.repeat(32);
  assert.throws(
    () => handoff.bindWorker('', workerA, false),
    /WRM_WORKER_NOT_ASSIGNED/,
  );
  assert.equal(handoff.bindWorker('', workerA, true), workerA);
  assert.equal(handoff.bindWorker(workerA, workerA, true), workerA);
  assert.throws(
    () => handoff.bindWorker(workerA, workerB, true),
    /WRM_WORKER_MISMATCH/,
  );
});

test('bounded base64 codec roundtrips binary chunks and rejects ambiguity', () => {
  const source = [0, 1, 2, 127, 128, 254, 255];
  const encoded = handoff.base64Encode(source);
  assert.deepEqual(handoff.base64Decode(encoded, 32), source);
  assert.throws(() => handoff.base64Decode('AA=A', 32), /WRM_BAD_BASE64/);
  assert.throws(
    () => handoff.base64Decode(handoff.base64Encode(new Array(33).fill(1)), 32),
    /WRM_BAD_BASE64/,
  );
});
