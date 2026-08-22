import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { selectAutomaticRoute } from '../src/auto-route.mjs';
import {
  applyProbeResult,
  createRecord,
  isAtHardCapacity,
  loadPersistentState,
  randomizedDelay,
  restoreSticky,
  savePersistentState,
  scoreRecord,
  selectRoute,
  setMaintenance,
} from '../src/route-core.mjs';

function baseConfig(nodes) {
  return {
    health: {
      intervalMs: 20_000,
      jitterRatio: 0.3,
      stickyTtlMs: 60_000,
      lossWeight: 1200,
      jitterWeight: 1.5,
      loadWeight: 900,
      overloadWeight: 2500,
      failureThreshold: 2,
      recoveryThreshold: 2,
      historySize: 8,
    },
    pools: [{ id: 'pool', maxRttMs: 5000, nodes }],
  };
}

function node(id, overrides = {}) {
  return {
    id,
    endpoint: `${id}:443`,
    protocols: ['vless-reality'],
    enabled: true,
    cost: 1,
    load: 0,
    softCapacity: 0.75,
    hardCapacity: 0.95,
    ...overrides,
  };
}

test('randomizedDelay stays inside configured jitter window', () => {
  assert.equal(randomizedDelay({ intervalMs: 20_000, jitterRatio: 0.3, random: () => 0 }), 14_000);
  assert.equal(randomizedDelay({ intervalMs: 20_000, jitterRatio: 0.3, random: () => 0.5 }), 20_000);
  assert.equal(randomizedDelay({ intervalMs: 20_000, jitterRatio: 0.3, random: () => 1 }), 26_000);
});

test('probe history derives jitter and failure rate with thresholds', () => {
  const record = createRecord(node('a'), 'pool');
  const health = { recoveryThreshold: 2, failureThreshold: 2, historySize: 8 };
  applyProbeResult(record, { success: true, rttMs: 40 }, health);
  assert.equal(record.healthy, false);
  applyProbeResult(record, { success: true, rttMs: 60 }, health);
  assert.equal(record.healthy, true);
  assert.equal(record.rttMs, 50);
  assert.ok(record.jitterMs > 0);
  applyProbeResult(record, { success: false, error: 'timeout' }, health);
  assert.equal(record.healthy, true);
  applyProbeResult(record, { success: false, error: 'timeout' }, health);
  assert.equal(record.healthy, false);
  assert.equal(record.failureRate, 0.5);
});

test('score penalizes loss jitter and load, not only RTT', () => {
  const clean = createRecord(node('clean'), 'pool');
  clean.healthy = true;
  clean.rttMs = 70;
  clean.jitterMs = 2;
  clean.failureRate = 0;

  const unstable = createRecord(node('unstable', { load: 0.7 }), 'pool');
  unstable.healthy = true;
  unstable.rttMs = 35;
  unstable.jitterMs = 30;
  unstable.failureRate = 0.2;

  const health = { jitterWeight: 1.5, lossWeight: 1200, loadWeight: 900 };
  assert.ok(scoreRecord(clean, health) < scoreRecord(unstable, health));
});

test('draining preserves an existing sticky assignment but gets no new clients', () => {
  const a = node('a');
  const b = node('b');
  const config = baseConfig([a, b]);
  const state = new Map([
    ['a', createRecord(a, 'pool')],
    ['b', createRecord(b, 'pool')],
  ]);
  state.get('a').healthy = true;
  state.get('a').rttMs = 30;
  state.get('a').failureRate = 0;
  state.get('b').healthy = true;
  state.get('b').rttMs = 50;
  state.get('b').failureRate = 0;
  const sticky = new Map();

  const first = selectRoute({ config, state, sticky, clientId: 'c1', poolId: 'pool', protocol: 'vless-reality', now: 1 });
  assert.equal(first.nodeId, 'a');
  setMaintenance(state.get('a'), 'draining');

  const sameClient = selectRoute({ config, state, sticky, clientId: 'c1', poolId: 'pool', protocol: 'vless-reality', now: 2 });
  assert.equal(sameClient.nodeId, 'a');
  assert.equal(sameClient.sticky, true);

  const newClient = selectRoute({ config, state, sticky, clientId: 'c2', poolId: 'pool', protocol: 'vless-reality', now: 2 });
  assert.equal(newClient.nodeId, 'b');
});

test('hard capacity blocks new assignments but does not invalidate existing sticky session', () => {
  const a = node('a', { load: 0.96 });
  const b = node('b', { load: 0.4 });
  const config = baseConfig([a, b]);
  const state = new Map([
    ['a', createRecord(a, 'pool')],
    ['b', createRecord(b, 'pool')],
  ]);
  for (const record of state.values()) {
    record.healthy = true;
    record.rttMs = record.node.id === 'a' ? 20 : 50;
    record.failureRate = 0;
  }
  assert.equal(isAtHardCapacity(state.get('a')), true);
  const sticky = new Map([
    ['old:pool:vless-reality', { nodeId: 'a', expiresAt: 1000 }],
  ]);
  const oldClient = selectRoute({ config, state, sticky, clientId: 'old', poolId: 'pool', protocol: 'vless-reality', now: 10 });
  assert.equal(oldClient.nodeId, 'a');
  const newClient = selectRoute({ config, state, sticky, clientId: 'new', poolId: 'pool', protocol: 'vless-reality', now: 10 });
  assert.equal(newClient.nodeId, 'b');
});

test('automatic routing never uses unlisted pool when includeUnlistedPools is false', () => {
  const ireland = node('ireland');
  const second = node('second');
  const config = {
    ...baseConfig([]),
    auto: {
      poolPriority: ['ireland-bs'],
      includeUnlistedPools: false,
      protocolPriority: ['vless-reality'],
    },
    pools: [
      { id: 'ireland-bs', maxRttMs: 5000, nodes: [ireland] },
      { id: 'second-server', maxRttMs: 5000, nodes: [second] },
    ],
  };
  const state = new Map([
    ['ireland', createRecord(ireland, 'ireland-bs')],
    ['second', createRecord(second, 'second-server')],
  ]);
  state.get('ireland').healthy = false;
  state.get('second').healthy = true;
  state.get('second').rttMs = 1;
  state.get('second').failureRate = 0;
  const result = selectAutomaticRoute({
    config,
    state,
    sticky: new Map(),
    clientId: 'client',
    now: 1,
  });
  assert.equal(result.error, 'NO_AUTOMATIC_ROUTE');
});

test('persistent state restores sticky and node health metadata', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wesi-route-'));
  const file = path.join(dir, 'state.json');
  const n = node('a');
  const record = createRecord(n, 'pool');
  record.healthy = true;
  record.rttMs = 42;
  record.jitterMs = 3;
  record.failureRate = 0.1;
  record.maintenance = 'draining';
  const state = new Map([['a', record]]);
  const sticky = new Map([['client:pool:vless-reality', { nodeId: 'a', expiresAt: Date.now() + 60_000 }]]);

  savePersistentState(file, state, sticky);
  const loaded = loadPersistentState(file);
  assert.equal(loaded.nodes.a.maintenance, 'draining');
  assert.equal(loaded.nodes.a.rttMs, 42);
  const restoredSticky = restoreSticky(loaded.sticky, Date.now());
  assert.equal(restoredSticky.get('client:pool:vless-reality').nodeId, 'a');
});
