import test from 'node:test';
import assert from 'node:assert/strict';
import {downloadGoogleVideo, artifactLimits} from './google-artifact.mjs';

function streamResponse(bytes, {status = 200, type = 'video/mp4'} = {}) {
  return new Response(bytes, {
    status,
    headers: {'content-type': type, 'content-length': String(bytes.length)},
  });
}

test('Veo download accepts only Google API HTTPS URL and video MIME', async () => {
  let auth = '';
  const result = await downloadGoogleVideo(
    'https://generativelanguage.googleapis.com/v1beta/files/video-1',
    'secret-key',
    {fetchImpl: async (_url, init) => {
      auth = init.headers['x-goog-api-key'];
      return streamResponse(Buffer.from('video'));
    }},
  );
  assert.equal(result.ok, true);
  assert.equal(auth, 'secret-key');
  assert.equal(result.mimeType, 'video/mp4');
  assert.equal(result.bytes.toString(), 'video');
});

test('Veo download rejects arbitrary host before network call', async () => {
  let called = false;
  const result = await downloadGoogleVideo(
    'https://evil.example/video',
    'secret-key',
    {fetchImpl: async () => { called = true; return streamResponse(Buffer.from('bad')); }},
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_PROVIDER_BAD_RESPONSE');
  assert.equal(called, false);
});

test('Veo download rejects non-video payload', async () => {
  const result = await downloadGoogleVideo(
    'https://storage.googleapis.com/example/video',
    'secret-key',
    {fetchImpl: async () => streamResponse(Buffer.from('{}'), {type: 'application/json'})},
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_PROVIDER_BAD_MEDIA');
});

test('video limit remains bounded', () => {
  assert.ok(artifactLimits.maxVideoBytes > 0);
  assert.ok(artifactLimits.maxVideoBytes <= 128 * 1024 * 1024);
});
