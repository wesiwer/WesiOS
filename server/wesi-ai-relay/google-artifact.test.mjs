import test from 'node:test';
import assert from 'node:assert/strict';
import {downloadGoogleVideo, artifactLimits} from './google-artifact.mjs';

function streamResponse(bytes, {status = 200, type = 'video/mp4', headers = {}} = {}) {
  return new Response(bytes, {
    status,
    headers: {
      'content-type': type,
      'content-length': String(bytes.length),
      ...headers,
    },
  });
}

test('Veo download accepts only Google API HTTPS URL and video MIME', async () => {
  let auth = '';
  let redirectMode = '';
  const result = await downloadGoogleVideo(
    'https://generativelanguage.googleapis.com/v1beta/files/video-1',
    'secret-key',
    {fetchImpl: async (_url, init) => {
      auth = init.headers['x-goog-api-key'];
      redirectMode = init.redirect;
      return streamResponse(Buffer.from('video'));
    }},
  );
  assert.equal(result.ok, true);
  assert.equal(auth, 'secret-key');
  assert.equal(redirectMode, 'manual');
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

test('Veo redirect to another Google API host is revalidated and keeps auth', async () => {
  const calls = [];
  const result = await downloadGoogleVideo(
    'https://generativelanguage.googleapis.com/v1beta/files/video-1',
    'secret-key',
    {fetchImpl: async (url, init) => {
      calls.push({url: String(url), key: init.headers['x-goog-api-key'], redirect: init.redirect});
      if (calls.length === 1) {
        return new Response(null, {
          status: 302,
          headers: {location: 'https://storage.googleapis.com/wesi-test/video.mp4'},
        });
      }
      return streamResponse(Buffer.from('redirected-video'));
    }},
  );
  assert.equal(result.ok, true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].redirect, 'manual');
  assert.equal(calls[1].url, 'https://storage.googleapis.com/wesi-test/video.mp4');
  assert.equal(calls[1].key, 'secret-key');
});

test('Veo redirect to arbitrary host is rejected before API key can reach it', async () => {
  const calls = [];
  const result = await downloadGoogleVideo(
    'https://generativelanguage.googleapis.com/v1beta/files/video-1',
    'secret-key',
    {fetchImpl: async (url, init) => {
      calls.push({url: String(url), key: init.headers['x-goog-api-key']});
      return new Response(null, {
        status: 302,
        headers: {location: 'https://evil.example/steal-key'},
      });
    }},
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_PROVIDER_BAD_RESPONSE');
  assert.equal(calls.length, 1, 'untrusted redirect target must never be requested');
  assert.equal(calls[0].key, 'secret-key');
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

test('video and redirect limits remain bounded', () => {
  assert.ok(artifactLimits.maxVideoBytes > 0);
  assert.ok(artifactLimits.maxVideoBytes <= 128 * 1024 * 1024);
  assert.ok(artifactLimits.maxRedirects > 0);
  assert.ok(artifactLimits.maxRedirects <= 5);
});
