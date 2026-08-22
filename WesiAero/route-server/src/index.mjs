import fs from 'node:fs';
import http from 'node:http';
import crypto from 'node:crypto';
import path from 'node:path';

import {
  applyProbeResult,
  createRecord,
  loadPersistentState,
  randomizedDelay,
  restoreSticky,
  savePersistentState,
  scoreRecord,
  selectRoute,
  setMaintenance,
} from './route-core.mjs';

const configPath = process.env.WESI_AERO_ROUTE_CONFIG || new URL('../config.json', import.meta.url);
const config = loadConfig(configPath);
const apiToken = process.env.WESI_AERO_ROUTE_TOKEN || '';
const statePath = path.resolve(
  process.cwd(),
  process.env.WESI_AERO_ROUTE_STATE || config.stateFile || 'data/route-state.json',
);

const persisted = loadPersistentState(statePath);
const state = new Map();
let sticky = restoreSticky(persisted.sticky);
let internetHealthy = true;
let stopped = false;
const timers = new Map();

for (const pool of config.pools) {
  for (const node of pool.nodes) {
    state.set(node.id, createRecord(node, pool.id, persisted.nodes[node.id]));
  }
}

function loadConfig(pathLike) {
  const file = pathLike instanceof URL ? pathLike : String(pathLike);
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(parsed.pools) || parsed.pools.length === 0) {
    throw new Error('config.pools must contain at least one pool');
  }
  parsed.health ??= {};
  parsed.health.intervalMs ??= 20_000;
  parsed.health.jitterRatio ??= 0.3;
  parsed.health.timeoutMs ??= 2_000;
  parsed.health.sampling ??= 2;
  parsed.health.failureThreshold ??= 2;
  parsed.health.recoveryThreshold ??= 2;
  parsed.health.historySize ??= 12;
  parsed.health.stickyTtlMs ??= 30 * 60_000;
  parsed.health.multiTargetQuorum ??= 1;
  parsed.health.expectedStatuses ??= [200, 204];
  parsed.listenHost ??= '127.0.0.1';
  parsed.listenPort ??= 8793;
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
      headers: { 'user-agent': 'WesiAero-RouteServer/0.2' },
    });
    const expected = Array.isArray(config.health.expectedStatuses)
      ? config.health.expectedStatuses.map(Number)
      : [200, 204];
    if (!expected.includes(response.status) && (response.status < 200 || response.status >= 400)) {
      throw new Error(`HTTP_${response.status}`);
    }
    return Math.max(1, Math.round(performance.now() - started));
  } finally {
    clearTimeout(timeout);
  }
}

async function checkInternet() {
  const urls = normalizeUrls(config.health.connectivityUrls ?? config.health.connectivityUrl);
  if (!urls.length) return true;
  for (const url of urls) {
    try {
      await timedHead(url, config.health.timeoutMs);
      return true;
    } catch {
      // Try next independent target.
    }
  }
  return false;
}

async function probeNode(record) {
  if (record.node.enabled === false || record.maintenance === 'offline') {
    record.healthy = false;
    record.lastError = record.maintenance === 'offline' ? 'MAINTENANCE_OFFLINE' : 'DISABLED';
    persist();
    return;
  }

  const targets = normalizeUrls(
    record.node.healthUrls ?? record.node.healthUrl ?? config.health.destinationUrls ?? config.health.destinationUrl,
  );
  if (!targets.length) {
    applyProbeResult(record, { success: false, error: 'NO_HEALTH_URL' }, config.health);
    persist();
    return;
  }

  const attempts = [];
  for (const target of targets) {
    for (let index = 0; index < Number(config.health.sampling); index += 1) {
      try {
        attempts.push({ ok: true, rttMs: await timedHead(target, config.health.timeoutMs) });
      } catch (error) {
        attempts.push({ ok: false, error: error instanceof Error ? error.message : String(error) });
      }
    }
  }

  const successful = attempts.filter((item) => item.ok);
  const quorum = Math.max(1, Number(record.node.healthQuorum ?? config.health.multiTargetQuorum ?? 1));
  const successfulTargets = countSuccessfulTargets(attempts, targets.length, Number(config.health.sampling));
  const success = successfulTargets >= Math.min(quorum, targets.length);
  const rttMs = successful.length
    ? Math.round(successful.reduce((sum, item) => sum + item.rttMs, 0) / successful.length)
    : null;
  const failure = attempts.findLast?.((item) => !item.ok) ?? attempts.find((item) => !item.ok);

  applyProbeResult(record, {
    success,
    rttMs,
    error: success ? null : (internetHealthy ? failure?.error ?? 'PROBE_FAILED' : 'CONNECTIVITY_UNAVAILABLE'),
  }, config.health);
  persist();
}

function countSuccessfulTargets(attempts, targetCount, sampling) {
  let successfulTargets = 0;
  for (let targetIndex = 0; targetIndex < targetCount; targetIndex += 1) {
    const start = targetIndex * sampling;
    const sample = attempts.slice(start, start + sampling);
    if (sample.some((item) => item.ok)) successfulTargets += 1;
  }
  return successfulTargets;
}

function normalizeUrls(value) {
  if (Array.isArray(value)) return value.map(String).map((item) => item.trim()).filter(Boolean);
  if (typeof value === 'string' && value.trim()) return [value.trim()];
  return [];
}

async function probeCycle(record) {
  if (stopped) return;
  internetHealthy = await checkInternet();
  await probeNode(record);
  scheduleProbe(record);
}

function scheduleProbe(record, immediate = false) {
  if (stopped) return;
  const existing = timers.get(record.node.id);
  if (existing) clearTimeout(existing);
  const delay = immediate
    ? 0
    : randomizedDelay({
        intervalMs: Number(config.health.intervalMs),
        jitterRatio: Number(config.health.jitterRatio),
      });
  const timer = setTimeout(() => {
    void probeCycle(record).catch((error) => {
      console.error(`[route-server] probe ${record.node.id} failed`, error);
      scheduleProbe(record);
    });
  }, delay);
  timer.unref();
  timers.set(record.node.id, timer);
}

function persist() {
  savePersistentState(statePath, state, sticky);
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
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', 'http://route.local');

    if (req.method === 'GET' && url.pathname === '/healthz') {
      return send(res, 200, {
        ok: true,
        internetHealthy,
        healthyNodes: [...state.values()].filter((record) => record.healthy).length,
        totalNodes: state.size,
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
          maintenance: record.maintenance,
          healthy: record.healthy,
          rttMs: record.rttMs,
          jitterMs: record.jitterMs,
          failureRate: record.failureRate,
          score: Math.round(scoreRecord(record, config.health)),
          load: Number(record.node.load ?? 0),
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
      const result = selectRoute({ config, state, sticky, clientId, poolId, protocol });
      if (result.error) {
        if (!internetHealthy && result.error === 'NO_HEALTHY_NODE') {
          return send(res, 503, { error: 'SERVER_CONNECTIVITY_UNAVAILABLE' });
        }
        return send(res, result.status, { error: result.error });
      }
      persist();
      return send(res, 200, result);
    }

    if (req.method === 'POST' && url.pathname === '/v1/release') {
      const body = await readJson(req);
      const clientId = String(body.clientId || '').trim();
      const poolId = String(body.poolId || '').trim();
      const protocol = body.protocol == null ? '*' : String(body.protocol).trim();
      if (!clientId || !poolId) return send(res, 400, { error: 'clientId and poolId are required' });
      sticky.delete(`${clientId}:${poolId}:${protocol}`);
      persist();
      return send(res, 200, { released: true });
    }

    const maintenance = url.pathname.match(/^\/v1\/nodes\/([a-zA-Z0-9._:-]{2,128})\/maintenance$/);
    if (req.method === 'PUT' && maintenance) {
      const record = state.get(maintenance[1]);
      if (!record) return send(res, 404, { error: 'NODE_NOT_FOUND' });
      const body = await readJson(req);
      try {
        setMaintenance(record, String(body.mode || ''));
      } catch {
        return send(res, 400, { error: 'mode must be online, draining or offline' });
      }
      persist();
      if (record.maintenance === 'online') scheduleProbe(record, true);
      return send(res, 200, {
        nodeId: record.node.id,
        maintenance: record.maintenance,
        healthy: record.healthy,
      });
    }

    return send(res, 404, { error: 'NOT_FOUND' });
  } catch (error) {
    const requestId = crypto.randomUUID();
    console.error(`[route-server] ${requestId}`, error);
    return send(res, 500, { error: 'INTERNAL_ERROR', requestId });
  }
});

for (const record of state.values()) scheduleProbe(record, true);

server.listen(config.listenPort, config.listenHost, () => {
  console.log(`[route-server] listening on http://${config.listenHost}:${config.listenPort}`);
});

function shutdown() {
  if (stopped) return;
  stopped = true;
  for (const timer of timers.values()) clearTimeout(timer);
  timers.clear();
  persist();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
