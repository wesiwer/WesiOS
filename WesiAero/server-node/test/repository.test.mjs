import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';

import { openDatabase } from '../src/database.mjs';
import { GatewayRepository, RepositoryError } from '../src/repository.mjs';

describe('GatewayRepository', () => {
  let database;
  let repository;
  let now;

  beforeEach(() => {
    database = openDatabase(':memory:');
    now = Date.parse('2026-08-20T12:00:00Z');
    repository = new GatewayRepository(database, {
      leaseTtlSeconds: 120,
      now: () => now,
    });
    repository.upsertNode({
      id: 'de-fra-01',
      city: 'Frankfurt',
      country: 'Germany',
      countryCode: 'DE',
      endpoint: 'gateway.example:443',
      protocols: ['vless-reality', 'amneziawg'],
      load: 0.2,
      online: true,
      recommended: true,
    });
  });

  afterEach(() => database.close());

  it('stores only a verifier and authenticates the one-time token', () => {
    const created = repository.createUser({
      displayName: 'Test User',
      maxSessions: 2,
      quotaBytes: 0,
    });
    const authenticated = repository.authenticate(created.token);
    assert.equal(authenticated.id, created.id);
    assert.equal(authenticated.maxSessions, 2);
    assert.equal(repository.authenticate(`${created.token}x`), null);

    const row = database.prepare('SELECT token_hash FROM users WHERE id = ?').get(created.id);
    assert.ok(ArrayBuffer.isView(row.token_hash));
    assert.equal(Buffer.from(row.token_hash).includes(Buffer.from(created.token)), false);
  });

  it('enforces the concurrent session limit atomically', () => {
    const created = repository.createUser({
      displayName: 'Single Session',
      maxSessions: 1,
      quotaBytes: 0,
    });
    const user = repository.authenticate(created.token);
    repository.reserveLease({
      user,
      deviceId: 'android-device-001',
      nodeId: 'de-fra-01',
      protocol: 'amneziawg',
    });
    assert.throws(
      () => repository.reserveLease({
        user,
        deviceId: 'windows-device-002',
        nodeId: 'de-fra-01',
        protocol: 'vless-reality',
      }),
      (error) => error instanceof RepositoryError &&
        error.code === 'SESSION_LIMIT_REACHED',
    );
    assert.equal(repository.activeLeaseCount(user.id), 1);
  });

  it('supersedes an old lease from the same device during reconnect', () => {
    const created = repository.createUser({
      displayName: 'Reconnect User',
      maxSessions: 1,
      quotaBytes: 0,
    });
    const user = repository.authenticate(created.token);
    const first = repository.reserveLease({
      user,
      deviceId: 'android-device-001',
      nodeId: 'de-fra-01',
      protocol: 'amneziawg',
    });
    const second = repository.reserveLease({
      user,
      deviceId: 'android-device-001',
      nodeId: 'de-fra-01',
      protocol: 'amneziawg',
    });
    assert.notEqual(first.id, second.id);
    assert.equal(repository.activeLeaseCount(user.id), 1);
  });

  it('blocks new leases after the monthly traffic quota is reached', () => {
    const created = repository.createUser({
      displayName: 'Quota User',
      maxSessions: 2,
      quotaBytes: 1024,
    });
    const user = repository.authenticate(created.token);
    repository.recordServerUsage({ userId: user.id, bytesIn: 700, bytesOut: 324 });
    assert.throws(
      () => repository.reserveLease({
        user,
        deviceId: 'android-device-001',
        nodeId: 'de-fra-01',
        protocol: 'amneziawg',
      }),
      (error) => error instanceof RepositoryError &&
        error.code === 'TRAFFIC_QUOTA_REACHED',
    );
  });

  it('expires a lease that misses its heartbeat', () => {
    const created = repository.createUser({
      displayName: 'Heartbeat User',
      maxSessions: 1,
      quotaBytes: 0,
    });
    const user = repository.authenticate(created.token);
    repository.reserveLease({
      user,
      deviceId: 'android-device-001',
      nodeId: 'de-fra-01',
      protocol: 'amneziawg',
    });
    now += 121_000;
    assert.equal(repository.activeLeaseCount(user.id), 0);
  });
});
