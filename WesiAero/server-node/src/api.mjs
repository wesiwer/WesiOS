import http from 'node:http';
import { URL } from 'node:url';

import { safeEqualText } from './credentials.mjs';
import { ProvisioningError } from './provisioner.mjs';
import { RepositoryError } from './repository.mjs';

export function createApiServer({ repository, provisioner, config }) {
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
        pathname,
        repository,
        provisioner,
        config,
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

async function route({ request, response, pathname, repository, provisioner, config }) {
  if (request.method === 'GET' && pathname === '/healthz') {
    sendJson(response, 200, { status: 'ok' });
    return 200;
  }

  if (pathname.startsWith('/v1/admin/')) {
    requireAdmin(request, config.adminToken);
    if (request.method === 'POST' && pathname === '/v1/admin/users') {
      const body = await readJson(request, config.bodyLimitBytes);
      const user = repository.createUser({
        displayName: body.displayName,
        maxSessions: body.maxSessions ?? 1,
        quotaBytes: body.quotaBytes ?? 0,
      });
      sendJson(response, 201, { user });
      return 201;
    }
    if (request.method === 'POST' && pathname === '/v1/admin/nodes') {
      const body = await readJson(request, config.bodyLimitBytes);
      const node = repository.upsertNode(body);
      sendJson(response, 200, { node });
      return 200;
    }
    if (request.method === 'POST' && pathname === '/v1/admin/usage') {
      const body = await readJson(request, config.bodyLimitBytes);
      const usage = repository.recordServerUsage({
        userId: body.userId,
        bytesIn: body.bytesIn,
        bytesOut: body.bytesOut,
      });
      sendJson(response, 200, { usage });
      return 200;
    }
    sendJson(response, 404, { error: { code: 'NOT_FOUND', message: 'Not found' } });
    return 404;
  }

  const user = requireUser(request, repository);

  if (request.method === 'GET' && pathname === '/v1/nodes') {
    sendJson(response, 200, { nodes: repository.listNodes() });
    return 200;
  }

  if (request.method === 'GET' && pathname === '/v1/usage') {
    const usage = repository.getUsage(user.id);
    sendJson(response, 200, {
      usage: {
        ...usage,
        quotaBytes: user.quotaBytes,
      },
    });
    return 200;
  }

  if (request.method === 'POST' && pathname === '/v1/leases') {
    const body = await readJson(request, config.bodyLimitBytes);
    const lease = repository.reserveLease({
      user,
      deviceId: body.deviceId,
      nodeId: body.nodeId,
      protocol: body.protocol,
    });
    try {
      const profile = await provisioner.profileFor({ user, lease });
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
    const lease = repository.heartbeatLease({
      userId: user.id,
      leaseId: heartbeatMatch[1],
    });
    sendJson(response, 200, { lease });
    return 200;
  }

  const leaseMatch = pathname.match(/^\/v1\/leases\/([0-9a-f-]{36})$/i);
  if (request.method === 'DELETE' && leaseMatch) {
    repository.closeLease({ userId: user.id, leaseId: leaseMatch[1] });
    response.writeHead(204, securityHeaders());
    response.end();
    return 204;
  }

  sendJson(response, 404, { error: { code: 'NOT_FOUND', message: 'Not found' } });
  return 404;
}

function requireUser(request, repository) {
  const header = request.headers.authorization;
  const token = typeof header === 'string' && header.startsWith('Bearer ')
    ? header.slice(7)
    : null;
  const user = repository.authenticate(token);
  if (!user) throw new HttpError(401, 'UNAUTHORIZED', 'Invalid access token');
  return user;
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

async function readJson(request, limit) {
  const contentType = request.headers['content-type'] || '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Expected application/json');
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
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new Error('not an object');
    }
    return body;
  } catch {
    throw new HttpError(400, 'INVALID_JSON', 'Invalid JSON body');
  }
}

function handleError(response, error) {
  if (error instanceof HttpError ||
      error instanceof RepositoryError ||
      error instanceof ProvisioningError) {
    const status = error.statusCode;
    sendJson(response, status, {
      error: { code: error.code, message: error.message },
    });
    return status;
  }
  sendJson(response, 500, {
    error: { code: 'INTERNAL_ERROR', message: 'Internal server error' },
  });
  return 500;
}

function sendJson(response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    ...securityHeaders(),
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
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

