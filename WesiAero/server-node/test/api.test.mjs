import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { createApiServer } from '../src/api.mjs';
import { openDatabase } from '../src/database.mjs';
import { GatewayRepository } from '../src/repository.mjs';

describe('control plane HTTP API', () => {
  let database;
  let repository;
  let server;
  let origin;
  let token;

  before(async () => {
    database = openDatabase(':memory:');
    repository = new GatewayRepository(database);
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
    token = repository.createUser({
      displayName: 'API User',
      maxSessions: 1,
      quotaBytes: 0,
    }).token;
    server = createApiServer({
      repository,
      provisioner: {
        async profileFor({ lease }) {
          return {
            protocol: lease.protocol,
            clientConfig: 'test-profile-that-is-never-used-as-a-real-tunnel',
          };
        },
      },
      config: {
        bodyLimitBytes: 65_536,
        adminToken: 'a'.repeat(32),
        technicalLogs: false,
      },
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    origin = `http://127.0.0.1:${address.port}`;
  });

  after(async () => {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
    database.close();
  });

  it('reports health without exposing internals', async () => {
    const response = await fetch(`${origin}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
    assert.equal(response.headers.get('cache-control'), 'no-store');
  });

  it('returns payment completion to the installed Wesi Aero app', async () => {
    const response = await fetch(`${origin}/v1/payment-return`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /^text\/html/);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.text();
    assert.match(body, /wesi-aero:\/\/payment-return/);
    assert.doesNotMatch(body, /claimToken|secretKey|cryptoPayToken/i);
  });

  it('requires a user token and creates a short-lived lease', async () => {
    const denied = await fetch(`${origin}/v1/nodes`);
    assert.equal(denied.status, 401);

    const nodes = await fetch(`${origin}/v1/nodes`, {
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(nodes.status, 200);
    assert.equal((await nodes.json()).nodes.length, 1);

    const lease = await fetch(`${origin}/v1/leases`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        deviceId: 'android-device-001',
        nodeId: 'de-fra-01',
        protocol: 'amneziawg',
      }),
    });
    assert.equal(lease.status, 201);
    const payload = await lease.json();
    assert.equal(payload.profile.protocol, 'amneziawg');
    assert.match(payload.lease.id, /^[0-9a-f-]{36}$/i);
  });
});
