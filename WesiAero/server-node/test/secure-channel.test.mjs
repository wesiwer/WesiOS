import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  decryptEnvelope,
  encryptEnvelope,
  ReplayGuard,
  SecureChannelError,
} from '../src/secure-channel.mjs';

describe('application-layer encrypted control channel', () => {
  const key = 'WA1-0123456789abcdef0123456789abcdef-abcdefghijklmnopqrstuvwxyz123456';

  it('encrypts and authenticates requests and responses', () => {
    const request = encryptEnvelope({
      action: 'nodes.list',
      privateValue: 'must-not-appear-in-envelope',
    }, key, { timestamp: 1_777_000_000_000 });
    assert.equal(JSON.stringify(request).includes('must-not-appear'), false);
    assert.deepEqual(decryptEnvelope(request, key), {
      action: 'nodes.list',
      privateValue: 'must-not-appear-in-envelope',
    });

    const response = encryptEnvelope({ ok: true, data: { revision: 42 } }, key, {
      requestId: request.requestId,
      timestamp: 1_777_000_000_010,
      direction: 'response',
    });
    assert.deepEqual(decryptEnvelope(response, key, { direction: 'response' }), {
      ok: true,
      data: { revision: 42 },
    });
  });

  it('detects tampering and replay', () => {
    const timestamp = Date.parse('2026-08-21T12:00:00Z');
    const guard = new ReplayGuard({ now: () => timestamp });
    const envelope = encryptEnvelope({ action: 'license.status' }, key, { timestamp });
    assert.deepEqual(decryptEnvelope(envelope, key, { replayGuard: guard }), {
      action: 'license.status',
    });
    assert.throws(
      () => decryptEnvelope(envelope, key, { replayGuard: guard }),
      (error) => error instanceof SecureChannelError && error.code === 'REPLAY_DETECTED',
    );
    const tampered = { ...envelope, tag: `${envelope.tag.slice(0, -1)}A` };
    assert.throws(
      () => decryptEnvelope(tampered, key),
      (error) => error instanceof SecureChannelError && error.code === 'DECRYPTION_FAILED',
    );
  });
});
