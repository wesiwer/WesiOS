import http from 'node:http';
import { URL } from 'node:url';

import { CommerceError } from './commerce.mjs';
import { safeEqualText } from './credentials.mjs';
import { PaymentError } from './payments.mjs';
import { ProvisioningError } from './provisioner.mjs';
import { RepositoryError } from './repository.mjs';
import {
  decryptEnvelope,
  encryptEnvelope,
  ReplayGuard,
  SecureChannelError,
} from './secure-channel.mjs';

export function createApiServer({
  repository,
  commerce = null,
  payments = null,
  provisioner,
  routeServer = null,
  config,
}) {
  const replayGuard = new ReplayGuard();
  return http.createServer(async (request, response) => {
    const startedAt = performance.now();
    let pathname = '/';
    let statusCode = 500;
    try {
      const url = new URL(request.url, 'http://localhost');
      pathname = url.pathname;
      statusCode = await route({
        request,
        response,
        url,
        pathname,
        repository,
        commerce,
        payments,
        provisioner,
        routeServer,
        config,
        replayGuard,
      });
    } catch (error) {
      statusCode = handleError(response, error);
    } finally {
      if (config.technicalLogs) {
        const durationMs = Math.round(performance.now() - startedAt);
        process.stdout.write(
          `${new Date().toISOString()} ${request.method} ${pathname} ${statusCode} ${durationMs}ms\n`,
        );
      }
    }
  });
}

async function route(context) {
  const {
    request,
    response,
    pathname,
    repository,
    commerce,
    payments,
    provisioner,
    routeServer,
    config,
    replayGuard,
  } = context;

  if (request.method === 'GET' && pathname === '/healthz') {
    sendJson(response, 200, commerce
      ? { status: 'ok', catalogRevision: commerce.revision }
      : { status: 'ok' });
    return 200;
  }

  if (request.method === 'GET' && pathname === '/v1/payment-return') {
    sendPaymentReturnPage(response);
    return 200;
  }

  if (request.method === 'POST' && pathname === '/v1/webhooks/yookassa') {
    requireCommerce(commerce, payments);
    const raw = await readBody(request, config.bodyLimitBytes, 'application/json');
    await payments.handleYooKassaWebhook(raw);
    sendJson(response, 200, { accepted: true });
    return 200;
  }

  if (request.method === 'POST' && pathname === '/v1/webhooks/crypto-pay') {
    requireCommerce(commerce, payments);
    const raw = await readBody(request, config.bodyLimitBytes, 'application/json');
    await payments.handleCryptoPayWebhook(
      raw,
      request.headers['crypto-pay-api-signature'],
    );
    sendJson(response, 200, { accepted: true });
    return 200;
  }

  if (commerce && request.method === 'GET' && pathname === '/v1/catalog') {
    const catalog = commerce.publicCatalog();
    const etag = `\"rev-${catalog.revision}\"`;
    if (request.headers['if-none-match'] === etag) {
      response.writeHead(304, {
        ...securityHeaders(),
        'cache-control': 'private, max-age=15',
        etag,
      });
      response.end();
      return 304;
    }
    sendJson(response, 200, catalog, {
      'cache-control': 'private, max-age=15',
      etag,
    });
    return 200;
  }

  if (commerce && request.method === 'POST' && pathname === '/v1/quotes') {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, {
      quote: commerce.quote({
        planId: body.planId,
        ipMode: body.ipMode,
        deviceLimit: body.deviceLimit,
        durationDays: body.durationDays,
      }),
    });
    return 200;
  }

  if (commerce && payments && request.method === 'POST' && pathname === '/v1/orders') {
    const body = await readJson(request, config.bodyLimitBytes);
    const created = commerce.createPayment({
      provider: body.provider,
      planId: body.planId,
      ipMode: body.ipMode,
      deviceLimit: body.deviceLimit,
      durationDays: body.durationDays,
      customerRef: body.customerRef ?? null,
      idempotencyKey: request.headers['idempotency-key'],
    });
    try {
      const payment = created.checkoutUrl
        ? created
        : await payments.createCheckout(created);
      sendJson(response, 201, {
        order: publicOrder(payment),
        claimToken: created.claimToken ?? null,
      });
      return 201;
    } catch (error) {
      if (created.status === 'pending') {
        commerce.updatePaymentStatus(created.id, 'failed', {
          code: error.code ?? 'PROVIDER_ERROR',
        });
      }
      throw error;
    }
  }

  const orderMatch = pathname.match(/^\/v1\/orders\/([0-9a-f-]{36})$/i);
  if (commerce && request.method === 'GET' && orderMatch) {
    const id = orderMatch[1];
    const claimToken = request.headers['x-order-claim'];
    if (!commerce.verifyPaymentClaim(id, claimToken)) {
      throw new HttpError(401, 'INVALID_ORDER_CLAIM', 'Invalid order claim token');
    }
    const payment = commerce.getPayment(id);
    if (!payment) throw new HttpError(404, 'PAYMENT_NOT_FOUND', 'Payment not found');
    const payload = { order: publicOrder(payment) };
    if (payment.status === 'paid' && payment.licenseId) {
      payload.license = commerce.getLicense(payment.licenseId);
      payload.key = commerce.revealLicenseKey(payment.licenseId);
    }
    sendJson(response, 200, payload);
    return 200;
  }

  if (pathname.startsWith('/v1/admin/')) {
    requireAdmin(request, config.adminToken);
    requireCommerce(commerce, payments, { paymentOptional: true });
    return routeAdmin(context);
  }

  if (commerce && request.method === 'POST' && pathname === '/v1/licenses/redeem') {
    const body = await readJson(request, config.bodyLimitBytes);
    const result = commerce.bindDevice({
      key: body.key,
      deviceId: body.deviceId,
      deviceName: body.deviceName,
      platform: body.platform,
    });
    sendJson(response, 200, {
      license: result.license,
      device: mapDeviceRow(result.device),
    });
    return 200;
  }

  if (commerce && request.method === 'POST' && pathname === '/v1/secure') {
    const key = requireBearer(request);
    const access = commerce.authenticateLicense(key);
    if (!access) throw new HttpError(401, 'UNAUTHORIZED', 'Invalid license key');
    const envelope = await readJson(request, config.bodyLimitBytes);
    const payload = decryptEnvelope(envelope, key, {
      direction: 'request',
      replayGuard,
    });
    let secureResponse;
    try {
      secureResponse = {
        ok: true,
        data: await dispatchSecureAction({
          payload,
          access,
          repository,
          commerce,
          provisioner,
          routeServer,
        }),
      };
    } catch (error) {
      if (!isExpectedError(error)) throw error;
      secureResponse = {
        ok: false,
        error: {
          code: error.code,
          message: error.message,
          status: error.statusCode,
        },
      };
    }
    sendJson(response, 200, encryptEnvelope(secureResponse, key, {
      requestId: envelope.requestId,
      direction: 'response',
    }));
    return 200;
  }

  const access = requireAccess(request, repository, commerce);

  if (request.method === 'GET' && pathname === '/v1/nodes') {
    sendJson(response, 200, { nodes: repository.listNodes() });
    return 200;
  }

  if (request.method === 'GET' && pathname === '/v1/license') {
    if (!access.license) {
      throw new HttpError(404, 'LICENSE_NOT_FOUND', 'Legacy access token has no license');
    }
    sendJson(response, 200, { license: access.license });
    return 200;
  }

  if (request.method === 'GET' && pathname === '/v1/usage') {
    const usage = repository.getUsage(access.user.id);
    sendJson(response, 200, {
      usage: { ...usage, quotaBytes: access.user.quotaBytes },
    });
    return 200;
  }

  if (request.method === 'POST' && pathname === '/v1/leases') {
    const body = await readJson(request, config.bodyLimitBytes);
    if (access.license) commerce.assertDeviceBound(access.license.id, body.deviceId);
    const resolved = await resolveLeaseRoute({
      commerce,
      routeServer,
      deviceId: body.deviceId,
      requestedNodeId: body.nodeId,
      requestedProtocol: body.protocol,
    });
    const lease = repository.reserveLease({
      user: access.user,
      deviceId: body.deviceId,
      nodeId: resolved.nodeId,
      protocol: resolved.protocol,
    });
    try {
      const profile = await provisioner.profileFor({ user: access.user, lease });
      sendJson(response, 201, { lease, profile });
      return 201;
    } catch (error) {
      repository.discardLease(lease.id);
      throw error;
    }
  }

  const heartbeatMatch = pathname.match(
    /^\/v1\/leases\/([0-9a-f-]{36})\/heartbeat$/i,
  );
  if (request.method === 'POST' && heartbeatMatch) {
    sendJson(response, 200, {
      lease: repository.heartbeatLease({
        userId: access.user.id,
        leaseId: heartbeatMatch[1],
      }),
    });
    return 200;
  }

  const leaseMatch = pathname.match(/^\/v1\/leases\/([0-9a-f-]{36})$/i);
  if (request.method === 'DELETE' && leaseMatch) {
    repository.closeLease({ userId: access.user.id, leaseId: leaseMatch[1] });
    response.writeHead(204, securityHeaders());
    response.end();
    return 204;
  }

  sendJson(response, 404, { error: { code: 'NOT_FOUND', message: 'Not found' } });
  return 404;
}

async function routeAdmin(context) {
  const {
    request,
    response,
    pathname,
    commerce,
    payments,
    config,
  } = context;

  if (request.method === 'GET' && pathname === '/v1/admin/snapshot') {
    sendJson(response, 200, commerce.adminSnapshot());
    return 200;
  }

  if (request.method === 'POST' && pathname === '/v1/admin/servers') {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, { server: commerce.upsertServer(body) });
    return 200;
  }

  const serverMatch = pathname.match(/^\/v1\/admin\/servers\/([a-z0-9-]{2,64})$/i);
  if (serverMatch && request.method === 'PUT') {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, {
      server: commerce.upsertServer({ ...body, id: serverMatch[1] }),
    });
    return 200;
  }
  if (serverMatch && request.method === 'DELETE') {
    if (!commerce.deleteServer(serverMatch[1])) {
      throw new HttpError(404, 'SERVER_NOT_FOUND', 'Server not found');
    }
    response.writeHead(204, securityHeaders());
    response.end();
    return 204;
  }

  if (request.method === 'POST' && pathname === '/v1/admin/plans') {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, { plan: commerce.upsertPlan(body) });
    return 200;
  }

  const planMatch = pathname.match(/^\/v1\/admin\/plans\/([a-z0-9-]{2,64})$/i);
  if (planMatch && request.method === 'PUT') {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, {
      plan: commerce.upsertPlan({ ...body, id: planMatch[1] }),
    });
    return 200;
  }
  if (planMatch && request.method === 'DELETE') {
    if (!commerce.deletePlan(planMatch[1])) {
      throw new HttpError(404, 'PLAN_NOT_FOUND', 'Plan not found');
    }
    response.writeHead(204, securityHeaders());
    response.end();
    return 204;
  }

  if (request.method === 'POST' && pathname === '/v1/admin/licenses') {
    const body = await readJson(request, config.bodyLimitBytes);
    const issued = commerce.createLicense({
      planId: body.planId ?? null,
      ipMode: body.ipMode,
      deviceLimit: body.deviceLimit,
      durationDays: body.durationDays,
      source: 'admin',
      note: body.note ?? '',
    });
    sendJson(response, 201, issued);
    return 201;
  }

  const licenseKeyMatch = pathname.match(
    /^\/v1\/admin\/licenses\/([0-9a-f-]{36})\/key$/i,
  );
  if (request.method === 'GET' && licenseKeyMatch) {
    sendJson(response, 200, { key: commerce.revealLicenseKey(licenseKeyMatch[1]) });
    return 200;
  }

  const licenseRevokeMatch = pathname.match(
    /^\/v1\/admin\/licenses\/([0-9a-f-]{36})\/revoke$/i,
  );
  if (request.method === 'POST' && licenseRevokeMatch) {
    if (!commerce.revokeLicense(licenseRevokeMatch[1])) {
      throw new HttpError(404, 'LICENSE_NOT_FOUND', 'License not found');
    }
    sendJson(response, 200, { license: commerce.getLicense(licenseRevokeMatch[1]) });
    return 200;
  }

  const licenseDevicesMatch = pathname.match(
    /^\/v1\/admin\/licenses\/([0-9a-f-]{36})\/devices$/i,
  );
  if (request.method === 'GET' && licenseDevicesMatch) {
    sendJson(response, 200, {
      devices: commerce.listDevices(licenseDevicesMatch[1]),
    });
    return 200;
  }

  const deviceMatch = pathname.match(
    /^\/v1\/admin\/licenses\/([0-9a-f-]{36})\/devices\/([a-zA-Z0-9._:-]{8,128})$/,
  );
  if (request.method === 'DELETE' && deviceMatch) {
    if (!commerce.revokeDevice(deviceMatch[1], deviceMatch[2])) {
      throw new HttpError(404, 'DEVICE_NOT_FOUND', 'Device not found');
    }
    response.writeHead(204, securityHeaders());
    response.end();
    return 204;
  }

  const settingMatch = pathname.match(
    /^\/v1\/admin\/payment-settings\/(mock|yookassa|crypto_pay)$/,
  );
  if (request.method === 'PUT' && settingMatch) {
    const body = await readJson(request, config.bodyLimitBytes);
    sendJson(response, 200, {
      setting: commerce.setPaymentSetting({
        provider: settingMatch[1],
        enabled: body.enabled,
        testMode: body.testMode,
        publicConfig: body.publicConfig ?? {},
      }),
      secretsConfigured: paymentSecretStatus(config),
    });
    return 200;
  }

  const mockMatch = pathname.match(
    /^\/v1\/admin\/payments\/([0-9a-f-]{36})\/confirm-mock$/i,
  );
  if (request.method === 'POST' && mockMatch) {
    sendJson(response, 200, payments.confirmMock(mockMatch[1]));
    return 200;
  }

  const reconcileMatch = pathname.match(
    /^\/v1\/admin\/payments\/([0-9a-f-]{36})\/reconcile$/i,
  );
  if (request.method === 'POST' && reconcileMatch) {
    sendJson(response, 200, await payments.reconcile(reconcileMatch[1]));
    return 200;
  }

  if (request.method === 'GET' && pathname === '/v1/admin/payment-secret-status') {
    sendJson(response, 200, paymentSecretStatus(config));
    return 200;
  }

  sendJson(response, 404, { error: { code: 'NOT_FOUND', message: 'Not found' } });
  return 404;
}

async function dispatchSecureAction({
  payload,
  access,
  repository,
  commerce,
  provisioner,
  routeServer,
}) {
  if (payload.action === 'license.status') {
    return { license: commerce.getLicense(access.license.id) };
  }
  if (payload.action === 'nodes.list') {
    return { nodes: repository.listNodes(), revision: commerce.revision };
  }
  if (payload.action === 'lease.create') {
    commerce.assertDeviceBound(access.license.id, payload.deviceId);
    const resolved = await resolveLeaseRoute({
      commerce,
      routeServer,
      deviceId: payload.deviceId,
      requestedNodeId: payload.nodeId,
      requestedProtocol: payload.protocol,
    });
    const lease = repository.reserveLease({
      user: access.user,
      deviceId: payload.deviceId,
      nodeId: resolved.nodeId,
      protocol: resolved.protocol,
    });
    try {
      const profile = await provisioner.profileFor({ user: access.user, lease });
      return { lease, profile };
    } catch (error) {
      repository.discardLease(lease.id);
      throw error;
    }
  }
  if (payload.action === 'lease.heartbeat') {
    commerce.assertDeviceBound(access.license.id, payload.deviceId);
    return {
      lease: repository.heartbeatLease({
        userId: access.user.id,
        leaseId: payload.leaseId,
      }),
    };
  }
  throw new HttpError(404, 'UNKNOWN_SECURE_ACTION', 'Unknown secure action');
}

async function resolveLeaseRoute({
  commerce,
  routeServer,
  deviceId,
  requestedNodeId,
  requestedProtocol,
}) {
  const server = commerce?.getServer?.(requestedNodeId);
  const poolId = server?.transportConfig?.routePoolId;
  if (!poolId) {
    return { nodeId: requestedNodeId, protocol: requestedProtocol };
  }
  if (!routeServer?.enabled) {
    throw new HttpError(503, 'ROUTE_SERVER_UNAVAILABLE', 'Automatic routing is unavailable');
  }
  try {
    const selected = await routeServer.select({
      clientId: deviceId,
      poolId,
      protocol: requestedProtocol,
    });
    return {
      nodeId: selected.nodeId || requestedNodeId,
      protocol: selected.protocol || requestedProtocol,
    };
  } catch (error) {
    throw new HttpError(
      Number(error?.statusCode) || 503,
      error?.code || 'ROUTE_SERVER_UNAVAILABLE',
      error?.message || 'Automatic routing is unavailable',
    );
  }
}

function requireAccess(request, repository, commerce) {
  const token = requireBearer(request);
  const legacy = repository.authenticate(token);
  if (legacy) return { user: legacy, license: null };
  if (commerce) {
    const licensed = commerce.authenticateLicense(token);
    if (licensed) return licensed;
  }
  throw new HttpError(401, 'UNAUTHORIZED', 'Invalid access token');
}

function requireBearer(request) {
  const header = request.headers.authorization;
  const token = typeof header === 'string' && header.startsWith('Bearer ')
    ? header.slice(7)
    : null;
  if (!token) throw new HttpError(401, 'UNAUTHORIZED', 'Bearer token is required');
  return token;
}

function requireAdmin(request, expectedToken) {
  if (!expectedToken) {
    throw new HttpError(404, 'ADMIN_DISABLED', 'Administrative API is disabled');
  }
  const actual = request.headers['x-admin-token'];
  if (!safeEqualText(actual, expectedToken)) {
    throw new HttpError(401, 'UNAUTHORIZED', 'Invalid administrative token');
  }
}

function requireCommerce(commerce, payments, { paymentOptional = false } = {}) {
  if (!commerce || (!paymentOptional && !payments)) {
    throw new HttpError(503, 'COMMERCE_UNAVAILABLE', 'Commerce service is unavailable');
  }
}

async function readJson(request, limit) {
  const body = await readBody(request, limit, 'application/json');
  try {
    const value = JSON.parse(body.toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('not an object');
    }
    return value;
  } catch {
    throw new HttpError(400, 'INVALID_JSON', 'Invalid JSON body');
  }
}

async function readBody(request, limit, expectedContentType) {
  const contentType = request.headers['content-type'] || '';
  if (!contentType.toLowerCase().startsWith(expectedContentType)) {
    throw new HttpError(415, 'UNSUPPORTED_MEDIA_TYPE', `Expected ${expectedContentType}`);
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) {
      throw new HttpError(413, 'BODY_TOO_LARGE', 'Request body is too large');
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function handleError(response, error) {
  if (isExpectedError(error)) {
    sendJson(response, error.statusCode, {
      error: { code: error.code, message: error.message },
    });
    return error.statusCode;
  }
  sendJson(response, 500, {
    error: { code: 'INTERNAL_ERROR', message: 'Internal server error' },
  });
  return 500;
}

function isExpectedError(error) {
  return error instanceof HttpError ||
    error instanceof RepositoryError ||
    error instanceof ProvisioningError ||
    error instanceof CommerceError ||
    error instanceof PaymentError ||
    error instanceof SecureChannelError;
}

function sendPaymentReturnPage(response) {
  const appUrl = 'wesi-aero://payment-return';
  const body = `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wesi Aero · Оплата</title>
  <style>
    html,body{height:100%;margin:0;background:#08090b;color:#f5f7fa;font-family:system-ui,-apple-system,Segoe UI,sans-serif}
    body{display:grid;place-items:center;padding:24px;box-sizing:border-box}
    main{max-width:520px;text-align:center}
    h1{font-size:28px;margin:0 0 12px}
    p{color:#aeb5c0;line-height:1.5;margin:0 0 24px}
    a{display:inline-block;padding:13px 20px;border-radius:14px;background:#f5f7fa;color:#08090b;text-decoration:none;font-weight:700}
  </style>
</head>
<body>
  <main>
    <h1>Возвращаемся в Wesi Aero</h1>
    <p>Приложение самостоятельно проверит платёж, получит ключ с сервера и привяжет его к этому устройству.</p>
    <a href="${appUrl}">Открыть Wesi Aero</a>
  </main>
  <script>setTimeout(function(){window.location.href='${appUrl}'},120);</script>
</body>
</html>`;
  response.writeHead(200, {
    ...securityHeaders(),
    'content-type': 'text/html; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
  });
  response.end(body);
}

function sendJson(response, statusCode, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    ...securityHeaders(),
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    ...extraHeaders,
  });
  response.end(body);
}

function securityHeaders() {
  return {
    'cache-control': 'no-store',
    'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'strict-transport-security': 'max-age=31536000; includeSubDomains',
  };
}

function publicOrder(payment) {
  return {
    id: payment.id,
    provider: payment.provider,
    status: payment.status,
    amountMinor: payment.amountMinor,
    currency: payment.currency,
    planId: payment.planId,
    ipMode: payment.ipMode,
    deviceLimit: payment.deviceLimit,
    durationDays: payment.durationDays,
    checkoutUrl: payment.checkoutUrl,
    createdAt: payment.createdAt,
    updatedAt: payment.updatedAt,
  };
}

function mapDeviceRow(row) {
  return {
    deviceId: row.device_id,
    deviceName: row.device_name,
    platform: row.platform,
    firstSeenAt: new Date(row.first_seen_at).toISOString(),
    lastSeenAt: new Date(row.last_seen_at).toISOString(),
  };
}

function paymentSecretStatus(config) {
  return {
    yookassa: Boolean(config.yookassaShopId && config.yookassaSecretKey),
    cryptoPay: Boolean(config.cryptoPayToken),
    mockAllowed: config.allowMockPayments === true,
    note: 'Secrets are configured only through server environment variables and are never returned.',
  };
}

class HttpError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.code = code;
  }
}
