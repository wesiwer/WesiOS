import {
  createHash,
  createHmac,
  timingSafeEqual,
} from 'node:crypto';

import { CommerceError } from './commerce.mjs';

export class PaymentError extends Error {
  constructor(code, message, statusCode = 502) {
    super(message);
    this.name = 'PaymentError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class PaymentOrchestrator {
  constructor(commerce, config, { fetchImpl = fetch, now = () => Date.now() } = {}) {
    this.commerce = commerce;
    this.config = config;
    this.fetch = fetchImpl;
    this.now = now;
  }

  async createCheckout(payment) {
    if (payment.provider === 'mock') return this.#createMock(payment);
    if (payment.provider === 'yookassa') return this.#createYooKassa(payment);
    if (payment.provider === 'crypto_pay') return this.#createCryptoPay(payment);
    throw new CommerceError('INVALID_PAYMENT_PROVIDER', 'Unsupported payment provider');
  }

  confirmMock(paymentId) {
    if (!this.config.allowMockPayments) {
      throw new PaymentError('MOCK_PAYMENTS_DISABLED', 'Mock payments are disabled', 403);
    }
    const payment = this.commerce.getPayment(paymentId);
    if (!payment || payment.provider !== 'mock') {
      throw new PaymentError('PAYMENT_NOT_FOUND', 'Mock payment not found', 404);
    }
    return this.commerce.fulfillPayment(paymentId, { verifiedBy: 'admin-test-action' });
  }

  async handleYooKassaWebhook(rawBody) {
    const notification = parseJson(rawBody);
    const externalId = notification?.object?.id;
    if (typeof externalId !== 'string') {
      throw new PaymentError('INVALID_WEBHOOK', 'YooKassa payment id is missing', 400);
    }
    const event = String(notification.event || 'unknown');
    const eventId = `${event}:${externalId}:${notification.object?.created_at || ''}`;
    if (!this.commerce.consumeWebhook('yookassa', eventId)) {
      return { duplicate: true };
    }
    const payment = this.commerce.getPaymentByExternal('yookassa', externalId);
    if (!payment) throw new PaymentError('PAYMENT_NOT_FOUND', 'Payment not found', 404);
    const verified = await this.#fetchYooKassaPayment(externalId);
    if (verified.status === 'succeeded' && verified.paid === true) {
      const amountMinor = parseAmountMinor(verified.amount?.value);
      if (amountMinor !== payment.amountMinor || verified.amount?.currency !== payment.currency) {
        throw new PaymentError('PAYMENT_AMOUNT_MISMATCH', 'Payment amount mismatch', 409);
      }
      return this.commerce.fulfillPayment(payment.id, {
        status: verified.status,
        paid: verified.paid,
        externalId,
      });
    }
    if (verified.status === 'canceled') {
      return this.commerce.updatePaymentStatus(payment.id, 'canceled', {
        status: verified.status,
        externalId,
      });
    }
    return { payment };
  }

  async handleCryptoPayWebhook(rawBody, signature) {
    this.#verifyCryptoSignature(rawBody, signature);
    const update = parseJson(rawBody);
    const requestDate = parseWebhookTimestamp(update.request_date);
    if (requestDate === null ||
        Math.abs(this.now() - requestDate) > 10 * 60 * 1000) {
      throw new PaymentError('STALE_WEBHOOK', 'Crypto Pay webhook timestamp is stale', 401);
    }
    const eventId = String(update.update_id ?? '');
    if (!this.commerce.consumeWebhook('crypto_pay', eventId)) {
      return { duplicate: true };
    }
    if (update.update_type !== 'invoice_paid') return { ignored: true };
    const invoice = update.payload;
    const externalId = String(invoice?.invoice_id ?? '');
    const payment = this.commerce.getPaymentByExternal('crypto_pay', externalId);
    if (!payment) throw new PaymentError('PAYMENT_NOT_FOUND', 'Payment not found', 404);
    if (invoice.status !== 'paid') {
      throw new PaymentError('PAYMENT_NOT_VERIFIED', 'Invoice is not paid', 409);
    }
    if (invoice.payload !== payment.id) {
      throw new PaymentError('PAYMENT_PAYLOAD_MISMATCH', 'Invoice payload mismatch', 409);
    }
    return this.commerce.fulfillPayment(payment.id, {
      invoiceId: externalId,
      status: invoice.status,
      paidAsset: invoice.paid_asset ?? null,
      paidAmount: invoice.paid_amount ?? null,
    });
  }

  async reconcile(paymentId) {
    const payment = this.commerce.getPayment(paymentId);
    if (!payment) throw new PaymentError('PAYMENT_NOT_FOUND', 'Payment not found', 404);
    if (payment.status !== 'pending') return { payment };
    if (payment.provider === 'mock') return { payment };
    if (payment.provider === 'yookassa') {
      if (!payment.externalId) return { payment };
      const verified = await this.#fetchYooKassaPayment(payment.externalId);
      if (verified.status === 'succeeded' && verified.paid === true &&
          parseAmountMinor(verified.amount?.value) === payment.amountMinor &&
          verified.amount?.currency === payment.currency) {
        return this.commerce.fulfillPayment(payment.id, {
          status: verified.status,
          externalId: payment.externalId,
          reconciled: true,
        });
      }
      return { payment };
    }
    if (!payment.externalId) return { payment };
    const invoice = await this.#callCryptoPay('getInvoices', {
      invoice_ids: payment.externalId,
    });
    const item = invoice.items?.[0];
    if (item?.status === 'paid' && item.payload === payment.id) {
      return this.commerce.fulfillPayment(payment.id, {
        invoiceId: payment.externalId,
        status: item.status,
        reconciled: true,
      });
    }
    return { payment };
  }

  #createMock(payment) {
    if (!this.config.allowMockPayments) {
      throw new PaymentError('MOCK_PAYMENTS_DISABLED', 'Mock payments are disabled', 403);
    }
    return this.commerce.attachProviderPayment(payment.id, {
      externalId: `mock-${payment.id}`,
      checkoutUrl: `wesi-aero://test-payment/${payment.id}`,
      providerData: { testMode: true },
    });
  }

  async #createYooKassa(payment) {
    this.#requireYooKassaCredentials();
    const response = await this.fetch('https://api.yookassa.ru/v3/payments', {
      method: 'POST',
      headers: {
        authorization: `Basic ${Buffer.from(
          `${this.config.yookassaShopId}:${this.config.yookassaSecretKey}`,
        ).toString('base64')}`,
        'content-type': 'application/json',
        'idempotence-key': payment.id,
      },
      body: JSON.stringify({
        amount: {
          value: (payment.amountMinor / 100).toFixed(2),
          currency: payment.currency,
        },
        capture: true,
        payment_method_data: { type: 'sbp' },
        confirmation: {
          type: 'redirect',
          return_url: this.config.paymentReturnUrl,
        },
        description: `Wesi Aero · ${payment.durationDays} days · ${payment.deviceLimit} device(s)`,
        metadata: { order_id: payment.id },
      }),
    });
    const body = await responseJson(response, 'YooKassa create payment failed');
    if (!response.ok || typeof body.id !== 'string' ||
        typeof body.confirmation?.confirmation_url !== 'string') {
      throw new PaymentError('PAYMENT_PROVIDER_ERROR', 'Invalid YooKassa response');
    }
    return this.commerce.attachProviderPayment(payment.id, {
      externalId: body.id,
      checkoutUrl: body.confirmation.confirmation_url,
      providerData: { status: body.status, test: body.test === true },
    });
  }

  async #fetchYooKassaPayment(externalId) {
    this.#requireYooKassaCredentials();
    const response = await this.fetch(
      `https://api.yookassa.ru/v3/payments/${encodeURIComponent(externalId)}`,
      {
        headers: {
          authorization: `Basic ${Buffer.from(
            `${this.config.yookassaShopId}:${this.config.yookassaSecretKey}`,
          ).toString('base64')}`,
        },
      },
    );
    return responseJson(response, 'YooKassa payment verification failed');
  }

  #requireYooKassaCredentials() {
    if (!this.config.yookassaShopId || !this.config.yookassaSecretKey) {
      throw new PaymentError(
        'PAYMENT_PROVIDER_NOT_CONFIGURED',
        'YooKassa credentials are not configured on the server',
        503,
      );
    }
  }

  async #createCryptoPay(payment) {
    const invoice = await this.#callCryptoPay('createInvoice', {
      currency_type: 'fiat',
      fiat: payment.currency,
      amount: (payment.amountMinor / 100).toFixed(2),
      accepted_assets: 'USDT,TON,BTC,ETH,LTC,BNB,TRX,USDC',
      description: `Wesi Aero · ${payment.durationDays} days · ${payment.deviceLimit} device(s)`,
      payload: payment.id,
      expires_in: 3600,
      paid_btn_name: 'callback',
      paid_btn_url: this.config.paymentReturnUrl,
    });
    return this.commerce.attachProviderPayment(payment.id, {
      externalId: String(invoice.invoice_id),
      checkoutUrl: invoice.bot_invoice_url ?? invoice.mini_app_invoice_url ?? invoice.web_app_invoice_url,
      providerData: { status: invoice.status, testMode: this.config.cryptoPayTestnet },
    });
  }

  async #callCryptoPay(method, body) {
    if (!this.config.cryptoPayToken) {
      throw new PaymentError(
        'PAYMENT_PROVIDER_NOT_CONFIGURED',
        'Crypto Pay token is not configured on the server',
        503,
      );
    }
    const host = this.config.cryptoPayTestnet
      ? 'https://testnet-pay.crypt.bot'
      : 'https://pay.crypt.bot';
    const response = await this.fetch(`${host}/api/${method}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'crypto-pay-api-token': this.config.cryptoPayToken,
      },
      body: JSON.stringify(body),
    });
    const payload = await responseJson(response, 'Crypto Pay request failed');
    if (!response.ok || payload.ok !== true || !payload.result) {
      throw new PaymentError('PAYMENT_PROVIDER_ERROR', 'Crypto Pay rejected request');
    }
    return payload.result;
  }

  #verifyCryptoSignature(rawBody, actualSignature) {
    if (!this.config.cryptoPayToken || typeof actualSignature !== 'string') {
      throw new PaymentError('INVALID_WEBHOOK_SIGNATURE', 'Missing webhook signature', 401);
    }
    const secret = createHash('sha256').update(this.config.cryptoPayToken).digest();
    const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
    const left = Buffer.from(actualSignature.toLowerCase());
    const right = Buffer.from(expected);
    if (left.length !== right.length || !timingSafeEqual(left, right)) {
      throw new PaymentError('INVALID_WEBHOOK_SIGNATURE', 'Invalid webhook signature', 401);
    }
  }
}

async function responseJson(response, message) {
  let body;
  try {
    body = await response.json();
  } catch {
    throw new PaymentError('PAYMENT_PROVIDER_ERROR', message);
  }
  if (!response.ok) {
    throw new PaymentError(
      'PAYMENT_PROVIDER_ERROR',
      typeof body.description === 'string' ? body.description : message,
    );
  }
  return body;
}

function parseJson(rawBody) {
  try {
    return JSON.parse(Buffer.from(rawBody).toString('utf8'));
  } catch {
    throw new PaymentError('INVALID_WEBHOOK', 'Invalid webhook JSON', 400);
  }
}

function parseWebhookTimestamp(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value < 1_000_000_000_000 ? value * 1000 : value;
  }
  if (typeof value !== 'string' || value.length === 0) return null;
  if (/^\d+$/.test(value)) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) return null;
    return numeric < 1_000_000_000_000 ? numeric * 1000 : numeric;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseAmountMinor(value) {
  if (typeof value !== 'string' || !/^\d+(?:\.\d{1,2})?$/.test(value)) return -1;
  const [whole, fraction = ''] = value.split('.');
  return Number.parseInt(whole, 10) * 100 + Number.parseInt(fraction.padEnd(2, '0'), 10);
}
