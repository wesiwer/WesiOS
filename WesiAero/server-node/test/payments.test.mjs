import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { afterEach, beforeEach, describe, it } from 'node:test';

import { CommerceRepository } from '../src/commerce.mjs';
import { openDatabase } from '../src/database.mjs';
import { PaymentError, PaymentOrchestrator } from '../src/payments.mjs';
import { GatewayRepository } from '../src/repository.mjs';
import { SecretVault } from '../src/secret-vault.mjs';

describe('verified payment adapters', () => {
  let database;
  let commerce;
  const now = Date.parse('2026-08-21T12:00:00Z');

  beforeEach(() => {
    database = openDatabase(':memory:');
    const gateway = new GatewayRepository(database, { now: () => now });
    commerce = new CommerceRepository(database, gateway, {
      now: () => now,
      secretVault: new SecretVault('payment-test-master-key-000000000000000000'),
    });
    commerce.seedDefaults();
  });

  afterEach(() => database.close());

  it('verifies Crypto Pay HMAC, timestamp, payload and deduplicates webhook', async () => {
    commerce.setPaymentSetting({
      provider: 'crypto_pay',
      enabled: true,
      testMode: true,
      publicConfig: { label: 'Crypto test' },
    });
    const order = commerce.createPayment({
      provider: 'crypto_pay',
      planId: 'aero-flex',
      ipMode: 'shared',
      deviceLimit: 1,
      durationDays: 30,
      idempotencyKey: 'crypto-order-0001',
    });
    commerce.attachProviderPayment(order.id, {
      externalId: '777001',
      checkoutUrl: 'https://t.me/CryptoTestnetBot?start=invoice',
    });
    const token = 'crypto-pay-test-token-000000000000';
    const orchestrator = new PaymentOrchestrator(commerce, {
      cryptoPayToken: token,
      cryptoPayTestnet: true,
    }, { now: () => now });
    const raw = Buffer.from(JSON.stringify({
      update_id: 1001,
      update_type: 'invoice_paid',
      request_date: Math.floor(now / 1000),
      payload: {
        invoice_id: 777001,
        status: 'paid',
        payload: order.id,
        paid_asset: 'USDT',
        paid_amount: '3.50',
      },
    }));
    const secret = createHash('sha256').update(token).digest();
    const signature = createHmac('sha256', secret).update(raw).digest('hex');
    const accepted = await orchestrator.handleCryptoPayWebhook(raw, signature);
    assert.equal(accepted.payment.status, 'paid');
    assert.match(accepted.key, /^WA1-/);
    assert.deepEqual(
      await orchestrator.handleCryptoPayWebhook(raw, signature),
      { duplicate: true },
    );
    await assert.rejects(
      () => orchestrator.handleCryptoPayWebhook(raw, '0'.repeat(64)),
      (error) => error instanceof PaymentError &&
        error.code === 'INVALID_WEBHOOK_SIGNATURE',
    );
  });

  it('does not trust YooKassa callback data and rechecks payment status', async () => {
    commerce.setPaymentSetting({
      provider: 'yookassa',
      enabled: true,
      testMode: true,
      publicConfig: { label: 'СБП test' },
    });
    const order = commerce.createPayment({
      provider: 'yookassa',
      planId: 'aero-flex',
      ipMode: 'shared',
      deviceLimit: 1,
      durationDays: 30,
      idempotencyKey: 'sbp-order-0001',
    });
    commerce.attachProviderPayment(order.id, {
      externalId: 'yk-payment-001',
      checkoutUrl: 'https://yookassa.ru/checkout/payments/v2/contract',
    });
    let verificationCalls = 0;
    const orchestrator = new PaymentOrchestrator(commerce, {
      yookassaShopId: 'shop-id',
      yookassaSecretKey: 'secret-key',
    }, {
      async fetchImpl(url) {
        verificationCalls++;
        assert.match(String(url), /yk-payment-001$/);
        return new Response(JSON.stringify({
          id: 'yk-payment-001',
          status: 'succeeded',
          paid: true,
          amount: { value: '349.00', currency: 'RUB' },
        }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      },
    });
    const result = await orchestrator.handleYooKassaWebhook(Buffer.from(JSON.stringify({
      event: 'payment.succeeded',
      object: {
        id: 'yk-payment-001',
        status: 'waiting_for_capture',
        paid: false,
        created_at: '2026-08-21T12:00:00Z',
      },
    })));
    assert.equal(verificationCalls, 1);
    assert.equal(result.payment.status, 'paid');
  });
});
