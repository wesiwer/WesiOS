import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {verifyMainRequest, resetReplayCache} from './auth.mjs';
import {parseGoogleRoute} from './google.mjs';

test('Relay accepts a fresh valid HMAC request', () => {
  resetReplayCache();
  const secret = 'x'.repeat(48);
  const body = JSON.stringify({requestId: 'wai_test_request_123'});
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto.createHmac('sha256', secret).update(`wai_test_request_123.${timestamp}.${body}`).digest('hex');
  const result = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_test_request_123',
    'x-wesi-signature': signature,
  }, body, secret);
  assert.equal(result.ok, true);
});

test('Relay rejects expired requests', () => {
  resetReplayCache();
  const secret = 'x'.repeat(48);
  const body = '{}';
  const timestamp = String(Math.floor(Date.now() / 1000) - 1000);
  const signature = crypto.createHmac('sha256', secret).update(`wai_test_request_123.${timestamp}.${body}`).digest('hex');
  const result = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_test_request_123',
    'x-wesi-signature': signature,
  }, body, secret);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_RELAY_REQUEST_EXPIRED');
});

test('Google route parser is allowlisted', () => {
  assert.deepEqual(parseGoogleRoute('google/model-name'), {model: 'model-name'});
  assert.equal(parseGoogleRoute('other/model-name'), null);
  assert.equal(parseGoogleRoute('google/../../secret'), null);
});

test('Relay rejects a signature that does not cover the request id', () => {
  resetReplayCache();
  const secret = 'x'.repeat(48);
  const body = JSON.stringify({requestId: 'wai_signed_id_0001'});
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto.createHmac('sha256', secret)
    .update(`wai_signed_id_0001.${timestamp}.${body}`)
    .digest('hex');
  const result = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_swapped_id_0002',
    'x-wesi-signature': signature,
  }, body, secret);
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_RELAY_AUTH_FAILED');
});

test('Relay accepts a request once and rejects the replay', () => {
  resetReplayCache();
  const secret = 'x'.repeat(48);
  const body = JSON.stringify({requestId: 'wai_once_only_0001'});
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto.createHmac('sha256', secret)
    .update(`wai_once_only_0001.${timestamp}.${body}`)
    .digest('hex');
  const headers = {
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_once_only_0001',
    'x-wesi-signature': signature,
  };

  const first = verifyMainRequest(headers, body, secret);
  const second = verifyMainRequest(headers, body, secret);

  assert.equal(first.ok, true);
  assert.equal(second.ok, false);
  assert.equal(second.code, 'WAI_RELAY_REPLAY_DETECTED');
});

test('Relay does not burn a request id on a forged signature', () => {
  resetReplayCache();
  const secret = 'x'.repeat(48);
  const body = JSON.stringify({requestId: 'wai_not_burned_001'});
  const timestamp = String(Math.floor(Date.now() / 1000));
  const forged = 'a'.repeat(64);
  const honest = crypto.createHmac('sha256', secret)
    .update(`wai_not_burned_001.${timestamp}.${body}`)
    .digest('hex');

  const attack = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_not_burned_001',
    'x-wesi-signature': forged,
  }, body, secret);
  const real = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_not_burned_001',
    'x-wesi-signature': honest,
  }, body, secret);

  assert.equal(attack.ok, false);
  assert.equal(real.ok, true, 'настоящий запрос обязан пройти после подделки');
});

/// Signing now has a single Main implementation in wesi_ai_lib.js. Chat,
/// voice and media routes must call that helper instead of cloning HMAC code;
/// this turns protocol drift into a test failure instead of a production 401.
test('Main server signs exactly what the relay verifies through one helper', async () => {
  const fs = await import('node:fs');
  const root = new URL('../../', import.meta.url);
  const lib = fs.readFileSync(new URL('server/pb_hooks/wesi_ai_lib.js', root), 'utf8');
  assert.match(
    lib,
    /hs256\(requestId \+ "\." \+ timestamp \+ "\." \+ raw/,
    'central Main helper must bind request id, timestamp and exact raw body',
  );

  const routeChecks = [
    ['server/pb_hooks/wesi_ai_routes.pb.js', /ai\.callRelay\(cfg, payload, relayRequestId\)/],
    ['server/pb_hooks/wesi_ai_voice.pb.js', /ai\.callRelayJson\(cfg,/],
    ['server/pb_hooks/wesi_ai_media_tools.js', /ai\.callRelayJson\(cfg,/],
    ['server/pb_hooks/wesi_ai_media_routes.pb.js', /ai\.callRelayJson\(cfg,/],
  ];
  for (const [path, pattern] of routeChecks) {
    const text = fs.readFileSync(new URL(path, root), 'utf8');
    assert.match(text, pattern, `${path}: route must use the shared signed Relay transport`);
  }
});
