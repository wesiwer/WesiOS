import fs from 'node:fs';
import http from 'node:http';
import crypto from 'node:crypto';

const configPath = process.env.WESI_AERO_ROUTE_CONFIG || new URL('../config.json', import.meta.url);
const config = loadConfig(configPath);
const apiToken = process.env.WESI_AERO_ROUTE_TOKEN || '';

const state = new Map();
const sticky = new Map();
let internetHealthy = true;
let probeTimer = null;

for (const pool of config.pools) {
  for (const node of pool.nodes) {
    state.set(node.id, {
      node,
      poolId: pool.id,
      healthy: false,
      rttMs: null,
      consecutiveFailures: 0,
      consecutiveSuccesses: 0,
      lastCheckedAt: null,
      lastError: null,
      samples: [],
    });
  }
}

function loadConfig(pathLike) {
  const path = pathLike instanceof URL ? pathLike : String(pathLike);
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(path, 'utf8'));
  } catch (error) {
    console.error(`[route-server] cannot read config: ${error.message}`);
    process.exit(1);
  }
  if (!Array.isArray(parsed.pools) || parsed.pools.length === 0) {
    throw new Error('config.pools must contain at least one pool');
  }
  parsed.health ??= {};
  parsed.health.intervalMs ??= 20_000;
  parsed.health.timeoutMs ??= 2_000;
  parsed.health.sampling ??= 2;
  parsed.health.failureThreshold ??= 2;
  parsed.health.recoveryThreshold ??= 2;
  parsed.health.stickyTtlMs ??= 30 * 60_000;
  parsed.health.switchHysteresisMs ??= 35;
  parsed.listenHost ??= '127.0.0.1';
  parsed.listenPort ??= 8792;
  return parsed;
}

async function timedHead(url, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const started = performance.now();
  try {
    const response = await fetch(url, {
      method: 'HEAD',
      redirect: 'manual',
      cache: 'no-store',
      signal: controller.signal,
      headers: { 'user-agent': 'WesiAero-RouteServer/0.1' },
    });
    const rttMs = Math.max(1, Math.round(performance.now() - started));
    if (response.status < 200 || response.status >= 500) {
      throw new Error(`HTTP_${response.status}`);
    }
    return rttMs;
  } finally {
    clearTimeout(timeout);
  }
}

async function checkInternet() {
  const url = config.health.connectivityUrl;
  if (!url) return true;
  try {
    await timedHead(url, config.health.timeoutMs);
    return true;
  } catch {
    return false;
  }
}

async function probeNode(record) {
  const { node } = record;
  if (node.enabled === false) {
    record.healthy = false;
    record.lastError = 'DISABLED';
    return;
  }
  const url = node.healthUrl || config.health.destinationUrl;
  if (!url) {
    record.healthy = false;
    record.lastError = 'NO_HEALTH_URL';
    return;
  }

  const round = [];
  let error = null;
  for (let i = 0; i < config.health.sampling; i += 1) {
    try {
      round.push(await timedHead(url, config.health.timeoutMs));
    } catch (cause) {
      error = cause instanceof Error ? cause.message : String(cause);
    }
  }

  record.lastCheckedAt = new Date().toISOString();
  if (round.length > 0) {
    const avg = Math.round(round.reduce((a, b) => a + b, 0) / round.length);
    record.samples.push(avg);
    record.samples = record.samples.slice(-config.health.sampling);
    record.rttMs = Math.round(record.samples.reduce((a, b) => a + b, 0) / record.samples.length);
    record.consecutiveSuccesses += 1;
    record.consecutiveFailures = 0;
    record.lastError = null;
    if (record.consecutiveSuccesses >= config.health.recoveryThreshold) {
      record.healthy = true;
    }
  } else {
    record.consecutiveFailures += 1;
    record.consecutiveSuccesses = 0;
    record.lastError = internetHealthy ? (error || 'PROBE_FAILED') : 'CONNECTIVITY_UNAVAILABLE';
    if (record.consecutiveFailures >= config.health.failureThreshold) {
      record.healthy = false;
    }
  }
}

async function probeAll() {
  internetHealthy = await checkInternet();
  await Promise.all([...state.values()].map(probeNode));
  expireSticky();
}

function expireSticky() {
  const now = Date.now();
  for (const [key, value] of sticky) {
    if (value.expiresAt <= now) sticky.delete(key);
  }
}

function score(record) {
  const rtt = record.rttMs ?? Number.MAX_SAFE_INTEGER / 4;
  const cost = Number(record.node.cost ?? 1);
  return rtt + Math.max(0, cost - 1) * 100;
}

function eligibleRecords(pool, protocol) {
  const maxRtt = Number(pool.maxRttMs ?? 5000);
  return pool.nodes
    .map((node) => state.get(node.id))
    .filter(Boolean)
    .filter((record) => record.node.enabled !== false)
    .filter((record) => !protocol || record.node.protocols?.includes(protocol))
    .filter((record) => record.healthy)
    .filter((record) => record.rttMs == null || record.rttMs <= maxRtt)
    .sort((a, b) => score(a) - score(b));
}

function selectRoute({ clientId, poolId, protocol }) {
  const pool = config.pools.find((candidate) => candidate.id === poolId);
  if (!pool) return { error: 'POOL_NOT_FOUND', status: 404 };

  const candidates = eligibleRecords(pool, protocol);
  if (candidates.length === 0) {
    return {
      error: internetHealthy ? 'NO_HEALTHY_NODE' : 'SERVER_CONNECTIVITY_UNAVAILABLE',
      status: 503,
    };
  }

  const key = `${clientId}:${poolId}:${protocol || '*'}`;
  const existing = sticky.get(key);
  if (existing && existing.expiresAt > Date.now()) {
    const current = state.get(existing.nodeId);
    if (current && candidates.includes(current)) {
      const best = candidates[0];
      const hysteresis = Number(config.health.switchHysteresisMs ?? 35);
      if (score(current) <= score(best) + hysteresis) {
        existing.expiresAt = Date.now() + config.health.stickyTtlMs;
        return selectedPayload(pool, current, true);
      }
    }
  }

  const chosen = candidates[0];
  sticky.set(key, {
    nodeId: chosen.node.id,
    expiresAt: Date.now() + config.health.stickyTtlMs,
  });
  return selectedPayload(pool, chosen, false);
}

function selectedPayload(pool, record, stickyHit) {
  return {
    poolId: pool.id,
    nodeId: record.node.id,
    endpoint: record.node.endpoint,
    protocols: record.node.protocols || [],
    countryCode: record.node.countryCode || '',
    rttMs: record.rttMs,
    healthy: record.healthy,
    sticky: stickyHit,
    profileRef: record.node.profileRef || null,
  };
}

function authorize(req) {
  if (!apiToken) return true;
  return req.headers.authorization === `Bearer ${apiToken}`;
}

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 64 * 1024) throw new Error('BODY_TOO_LARGE');
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', 'http://route.local');

    if (req.method === 'GET' && url.pathname === '/healthz') {
      return send(res, 200, {
        ok: true,
        internetHealthy,
        nodes: [...state.values()].filter((record) => record.healthy).length,
      });
    }

    if (!authorize(req)) return send(res, 401, { error: 'UNAUTHORIZED' });

    if (req.method === 'GET' && url.pathname === '/v1/nodes') {
      return send(res, 200, {
        internetHealthy,
        nodes: [...state.values()].map((record) => ({
          id: record.node.id,
          poolId: record.poolId,
          endpoint: record.node.endpoint,
          protocols: record.node.protocols || [],
          healthy: record.healthy,
          rttMs: record.rttMs,
          lastCheckedAt: record.lastCheckedAt,
          lastError: record.lastError,
        })),
      });
    }

    if (req.method === 'POST' && url.pathname === '/v1/select') {
      const body = await readJson(req);
      const clientId = String(body.clientId || '').trim();
      const poolId = String(body.poolId || '').trim();
      const protocol = body.protocol == null ? null : String(body.protocol).trim();
      if (!clientId || !poolId) {
        return send(res, 400, { error: 'clientId and poolId are required' });
      }
      const result = selectRoute({ clientId, poolId, protocol });
      if (result.error) return send(res, result.status, { error: result.error });
      return send(res, 200, result);
    }

    if (req.method === 'POST' && url.pathname === '/v1/release') {
      const body = await readJson(req);
      const clientId = String(body.clientId || '').trim();
      const poolId = String(body.poolId || '').trim();
      const protocol = body.protocol == null ? '*' : String(body.protocol).trim();
      if (!clientId || !poolId) return send(res, 400, { error: 'clientId and poolId are required' });
      sticky.delete(`${clientId}:${poolId}:${protocol}`);
      return send(res, 200, { released: true });
    }

    return send(res, 404, { error: 'NOT_FOUND' });
  } catch (error) {
    const requestId = crypto.randomUUID();
    console.error(`[route-server] ${requestId}`, error);
    return send(res, 500, { error: 'INTERNAL_ERROR', requestId });
  }
});

await probeAll();
probeTimer = setInterval(() => {
  void probeAll().catch((error) => console.error('[route-server] probe failed', error));
}, config.health.intervalMs);
probeTimer.unref();

server.listen(config.listenPort, config.listenHost, () => {
  console.log(`[route-server] listening on http://${config.listenHost}:${config.listenPort}`);
});

function shutdown() {
  if (probeTimer) clearInterval(probeTimer);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
