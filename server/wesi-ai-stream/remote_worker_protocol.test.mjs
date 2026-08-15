import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const rw = require('../pb_hooks/wesi_ai_remote_worker_lib.js');

const security = {
  sha256(value) {
    return crypto.createHash('sha256').update(String(value), 'utf8').digest('hex');
  },
  hs256(value, key) {
    return crypto.createHmac('sha256', String(key)).update(String(value), 'utf8').digest('hex');
  },
};

const credentialId = 'c'.repeat(32);
const workerId = 'w'.repeat(32);
const nonce = 'n'.repeat(32);
const secret = 'bootstrap-secret-'.repeat(4);
const path = '/api/wesi/ai/workers/heartbeat';
const nowMs = Date.UTC(2026, 7, 15, 16, 50, 0);

test('server verifies the same derived HMAC request contract as Dart', () => {
  const payloadJson = JSON.stringify({v: 1, sentAt: new Date(nowMs).toISOString()});
  const requestKey = rw.deriveRequestKey(secret, security);
  assert.equal(requestKey, security.sha256(secret));
  const bodySha256 = security.sha256(payloadJson);
  const canonical = rw.canonicalRequest({
    credentialId,
    workerId,
    timestampMs: nowMs,
    nonce,
    method: 'POST',
    path,
    bodySha256,
  });
  const signature = security.hs256(canonical, requestKey);
  assert.equal(
    rw.verifySignedRequest({
      credentialId,
      workerId,
      timestampMs: nowMs,
      nonce,
      method: 'POST',
      path,
      bodySha256,
      signature,
      payloadJson,
      requestKey,
      nowMs: nowMs + 1000,
    }, security).ok,
    true,
  );

  assert.equal(
    rw.verifySignedRequest({
      credentialId,
      workerId,
      timestampMs: nowMs,
      nonce,
      method: 'POST',
      path,
      bodySha256,
      signature,
      payloadJson: payloadJson + ' ',
      requestKey,
      nowMs,
    }, security).code,
    'WRW_BODY_TAMPERED',
  );
  assert.equal(
    rw.verifySignedRequest({
      credentialId,
      workerId,
      timestampMs: nowMs,
      nonce,
      method: 'POST',
      path,
      bodySha256,
      signature,
      payloadJson,
      requestKey,
      nowMs: nowMs + 180000,
    }, security).code,
    'WRW_UNAUTHORIZED',
  );
});

test('durable replay window rejects the same request nonce', () => {
  const first = rw.acceptNonce([], nonce, nowMs);
  assert.equal(first.ok, true);
  const replay = rw.acceptNonce(first.values, nonce, nowMs + 1000);
  assert.equal(replay.ok, false);
  const later = rw.acceptNonce(first.values, nonce, nowMs + 4 * 60 * 1000);
  assert.equal(later.ok, true);
});

test('pairing ticket validation is short lived and binds worker fingerprint', () => {
  const ticket = rw.validateTicket({
    ticketId: 't'.repeat(32),
    workerId,
    workerName: 'Desktop worker',
    deviceFingerprint: 'a'.repeat(64),
    nonce,
    expiresAtMs: nowMs + 5 * 60 * 1000,
  }, nowMs);
  assert.equal(ticket.workerId, workerId);
  assert.throws(
    () => rw.validateTicket({...ticket, expiresAtMs: nowMs - 1}, nowMs),
    /WRW_BAD_PAIRING_TICKET/,
  );
});

test('heartbeat accepts only the authenticated desktop worker identity', () => {
  const heartbeat = {
    v: 1,
    sentAt: new Date(nowMs).toISOString(),
    worker: {
      id: workerId,
      name: 'Desktop worker',
      platform: 'windows',
      status: 'online',
      policyAllowed: true,
      appForeground: true,
      backgroundExecutionAllowed: true,
      cpuCores: 8,
      cpuLoadPercent: 25,
      totalRamMb: 16384,
      availableRamMb: 12000,
      gpuName: 'GPU',
      totalGpuVramMb: 8192,
      freeGpuVramMb: 7000,
      freeDiskMb: 100000,
      thermalState: 'nominal',
      powerMode: 'normal',
      capabilities: ['flutter', 'build'],
      installedPacks: ['developer'],
      activeLightJobs: 0,
      activeCpuJobs: 0,
      activeHeavyJobs: 0,
      activeGpuJobs: 0,
    },
  };
  assert.equal(rw.validateHeartbeat(heartbeat, workerId, nowMs), heartbeat);
  assert.throws(
    () => rw.validateHeartbeat(heartbeat, 'x'.repeat(32), nowMs),
    /WRW_BAD_HEARTBEAT/,
  );
});

test('mailbox message validator rejects unbounded or unknown messages', () => {
  const valid = {
    v: 1,
    messageId: 'msg-1',
    jobId: 'job-1',
    kind: 'assignment',
    sequence: 11,
    createdAt: new Date(nowMs).toISOString(),
    payload: {leaseId: 'l'.repeat(32), generation: 1},
  };
  assert.equal(rw.validateMessage(valid), valid);
  assert.throws(
    () => rw.validateMessage({...valid, kind: 'shell'}),
    /WRW_BAD_JOB_MESSAGE/,
  );
});
