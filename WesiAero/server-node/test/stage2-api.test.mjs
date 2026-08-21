import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { createApiServer } from '../src/api.mjs';
import { CommerceRepository } from '../src/commerce.mjs';
import { openDatabase } from '../src/database.mjs';
import { PaymentOrchestrator } from '../src/payments.mjs';
import { GatewayRepository } from '../src/repository.mjs';
import { SecretVault } from '../src/secret-vault.mjs';
import { decryptEnvelope, encryptEnvelope } from '../src/secure-channel.mjs';

describe('Wesi Aero client, admin and server integration', () => {
  let database;
  let server;
  let origin;
  const adminToken = 'admin-token-for-stage-two-tests-000000000';

  before(async () => {
    database = openDatabase(':memory:');
    const repository = new GatewayRepository(database);
    const commerce = new CommerceRepository(database, repository, {
      secretVault: new SecretVault('stage-two-test-master-key-000000000000000'),
    });
    commerce.seedDefaults();
    commerce.upsertServer({
      id: 'de-fra-01',
      displayName: 'Frankfurt One',
      city: 'Frankfurt',
      country: 'Germany',
      countryCode: 'DE',
      endpoint: 'gateway.example:443',
      protocols: ['vless-reality', 'amneziawg'],
      load: 0.2,
      online: true,
      recommended: true,
      capacity: 500,
      tags: ['eu'],
      transportConfig: { reality: { port: 443 } },
    });
    const config = {
      bodyLimitBytes: 262_144,
      adminToken,
      technicalLogs: false,
      allowMockPayments: true,
      yookassaShopId: null,
      yookassaSecretKey: null,
      cryptoPayToken: null,
    };
    const payments = new PaymentOrchestrator(commerce, config);
    server = createApiServer({
      repository,
      commerce,
      payments,
      provisioner: {
        async profileFor({ lease }) {
          return {
            protocol: lease.protocol,
            clientConfig: 'encrypted-test-profile-for-round-trip',
          };
        },
      },
      config,
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    origin = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
    database.close();
  });

  it('propagates an admin server change through the revisioned client catalog', async () => {
    const beforeCatalog = await json(`${origin}/v1/catalog`);
    const revision = beforeCatalog.revision;
    const changed = await fetch(`${origin}/v1/admin/servers/de-fra-01`, {
      method: 'PUT',
      headers: adminHeaders(),
      body: JSON.stringify({
        displayName: 'Frankfurt Aero Prime',
        city: 'Frankfurt',
        country: 'Germany',
        countryCode: 'DE',
        endpoint: 'gateway-2.example:443',
        protocols: ['vless-reality'],
        load: 0.1,
        online: true,
        recommended: true,
        capacity: 900,
        tags: ['eu', 'prime'],
        transportConfig: { reality: { port: 443, serverName: 'example.org' } },
      }),
    });
    assert.equal(changed.status, 200);
    const afterCatalog = await json(`${origin}/v1/catalog`);
    assert.ok(afterCatalog.revision > revision);
    assert.equal(afterCatalog.servers[0].displayName, 'Frankfurt Aero Prime');
    assert.equal(JSON.stringify(afterCatalog).includes('serverName'), false);
  });

  it('creates, confirms, claims and automatically redeems a paid key', async () => {
    const orderResponse = await fetch(`${origin}/v1/orders`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'idempotency-key': 'api-order-stage2-0001',
      },
      body: JSON.stringify({
        provider: 'mock',
        planId: 'aero-flex',
        ipMode: 'shared',
        deviceLimit: 1,
        durationDays: 7,
      }),
    });
    assert.equal(orderResponse.status, 201);
    const created = await orderResponse.json();
    assert.equal(created.order.status, 'pending');
    assert.ok(created.claimToken.length > 32);

    const confirmed = await fetch(
      `${origin}/v1/admin/payments/${created.order.id}/confirm-mock`,
      { method: 'POST', headers: { 'x-admin-token': adminToken } },
    );
    assert.equal(confirmed.status, 200);

    const claimed = await fetch(`${origin}/v1/orders/${created.order.id}`, {
      headers: { 'x-order-claim': created.claimToken },
    });
    assert.equal(claimed.status, 200);
    const claim = await claimed.json();
    assert.equal(claim.order.status, 'paid');
    assert.match(claim.key, /^WA1-/);

    const redeemed = await fetch(`${origin}/v1/licenses/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        key: claim.key,
        deviceId: 'android-device-001',
        deviceName: 'Pixel',
        platform: 'android',
      }),
    });
    assert.equal(redeemed.status, 200);

    const denied = await fetch(`${origin}/v1/licenses/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        key: claim.key,
        deviceId: 'windows-device-002',
        deviceName: 'PC',
        platform: 'windows',
      }),
    });
    assert.equal(denied.status, 409);
    assert.equal((await denied.json()).error.code, 'DEVICE_LIMIT_EXCEEDED');

    const request = encryptEnvelope({ action: 'nodes.list' }, claim.key);
    const secure = await fetch(`${origin}/v1/secure`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${claim.key}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(request),
    });
    assert.equal(secure.status, 200);
    const encryptedResponse = await secure.json();
    assert.equal(JSON.stringify(encryptedResponse).includes('Frankfurt'), false);
    const clear = decryptEnvelope(encryptedResponse, claim.key, { direction: 'response' });
    assert.equal(clear.ok, true);
    assert.equal(clear.data.nodes[0].id, 'de-fra-01');
  });

  function adminHeaders() {
    return {
      'x-admin-token': adminToken,
      'content-type': 'application/json',
    };
  }
});

async function json(url) {
  const response = await fetch(url);
  assert.equal(response.status, 200);
  return response.json();
}
