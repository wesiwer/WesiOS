import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';

import { CommerceError, CommerceRepository } from '../src/commerce.mjs';
import { openDatabase } from '../src/database.mjs';
import { GatewayRepository } from '../src/repository.mjs';
import { SecretVault } from '../src/secret-vault.mjs';

describe('tariffs, licenses, devices and orders', () => {
  let database;
  let gateway;
  let commerce;
  let now;

  beforeEach(() => {
    database = openDatabase(':memory:');
    now = Date.parse('2026-08-21T12:00:00Z');
    gateway = new GatewayRepository(database, { now: () => now });
    commerce = new CommerceRepository(database, gateway, {
      now: () => now,
      secretVault: new SecretVault('test-master-key-that-is-longer-than-32-characters'),
    });
    commerce.seedDefaults();
  });

  afterEach(() => database.close());

  it('calculates dynamic pricing on the server', () => {
    const quote = commerce.quote({
      planId: 'aero-flex',
      ipMode: 'shared',
      deviceLimit: 3,
      durationDays: 30,
    });
    assert.equal(quote.amountMinor, 34900 + 12900 * 2);
    assert.equal(quote.currency, 'RUB');
  });

  it('stores recoverable keys encrypted and enforces the device seat limit', () => {
    const issued = commerce.createLicense({
      planId: 'aero-flex',
      ipMode: 'dedicated',
      deviceLimit: 1,
      durationDays: 7,
      source: 'admin',
    });
    assert.match(issued.key, /^WA1-[0-9a-f]{32}-/i);
    assert.equal(commerce.revealLicenseKey(issued.license.id), issued.key);
    const stored = database.prepare(`
      SELECT encrypted_key FROM licenses WHERE id = ?
    `).get(issued.license.id).encrypted_key;
    assert.equal(stored.includes(issued.key), false);

    commerce.bindDevice({
      key: issued.key,
      deviceId: 'android-device-001',
      deviceName: 'Pixel',
      platform: 'android',
    });
    assert.throws(
      () => commerce.bindDevice({
        key: issued.key,
        deviceId: 'windows-device-002',
        deviceName: 'PC',
        platform: 'windows',
      }),
      (error) => error instanceof CommerceError &&
        error.code === 'DEVICE_LIMIT_EXCEEDED',
    );
  });

  it('rejects an expired key based on server time', () => {
    const issued = commerce.createLicense({
      planId: 'aero-flex',
      ipMode: 'shared',
      deviceLimit: 2,
      durationDays: 7,
      source: 'admin',
    });
    now += 7 * 86_400_000 + 1;
    assert.throws(
      () => commerce.authenticateLicense(issued.key),
      (error) => error instanceof CommerceError && error.code === 'LICENSE_EXPIRED',
    );
  });

  it('fulfills a payment once and protects status with an order claim token', () => {
    const order = commerce.createPayment({
      provider: 'mock',
      planId: 'aero-flex',
      ipMode: 'shared',
      deviceLimit: 2,
      durationDays: 30,
      customerRef: 'test-customer',
      idempotencyKey: 'order-test-0001',
    });
    assert.equal(commerce.verifyPaymentClaim(order.id, order.claimToken), true);
    assert.equal(commerce.verifyPaymentClaim(order.id, `${order.claimToken}x`), false);
    const fulfilled = commerce.fulfillPayment(order.id, { verified: true });
    assert.equal(fulfilled.payment.status, 'paid');
    assert.equal(fulfilled.license.deviceLimit, 2);
    assert.equal(commerce.revealLicenseKey(fulfilled.license.id), fulfilled.key);
    assert.equal(commerce.fulfillPayment(order.id).license.id, fulfilled.license.id);
  });
});
