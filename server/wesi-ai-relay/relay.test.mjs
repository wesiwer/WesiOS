import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {verifyMainRequest} from './auth.mjs';
import {parseGoogleRoute} from './google.mjs';

test('Relay accepts a fresh valid HMAC request', () => {
  const secret = 'x'.repeat(48);
  const body = JSON.stringify({requestId: 'wai_test_request_123'});
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = crypto.createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
  const result = verifyMainRequest({
    'x-wesi-timestamp': timestamp,
    'x-wesi-request-id': 'wai_test_request_123',
    'x-wesi-signature': signature,
  }, body, secret);
  assert.equal(result.ok, true);
});

test('Relay rejects expired requests', () => {
  const secret = 'x'.repeat(48);
  const body = '{}';
  const timestamp = String(Math.floor(Date.now() / 1000) - 1000);
  const signature = crypto.createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
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
