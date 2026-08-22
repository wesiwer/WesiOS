import fs from 'node:fs';
import path from 'node:path';

export function average(values) {
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

export function standardDeviation(values) {
  if (values.length < 2) return 0;
  const mean = average(values);
  const variance = average(values.map((value) => (value - mean) ** 2));
  return Math.sqrt(variance);
}

export function randomizedDelay({ intervalMs, jitterRatio = 0.3, random = Math.random }) {
  const ratio = Math.max(0, Math.min(0.95, Number(jitterRatio) || 0));
  const spread = intervalMs * ratio;
  return Math.max(250, Math.round(intervalMs - spread + random() * spread * 2));
}

export function createRecord(node, poolId, restored = null) {
  const previous = restored ?? {};
  return {
    node,
    poolId,
    maintenance: normalizeMaintenance(previous.maintenance ?? node.maintenance ?? 'online'),
    healthy: previous.healthy === true,
    rttMs: finiteOrNull(previous.rttMs),
    jitterMs: finiteOrZero(previous.jitterMs),
    failureRate: clamp01(previous.failureRate ?? 1),
    recentFailurePenalty: Math.max(0, Number(previous.recentFailurePenalty ?? 0)),
    consecutiveFailures: Math.max(0, Number(previous.consecutiveFailures ?? 0)),
    consecutiveSuccesses: Math.max(0, Number(previous.consecutiveSuccesses ?? 0)),
    lastCheckedAt: previous.lastCheckedAt ?? null,
    lastError: previous.lastError ?? null,
    samples: Array.isArray(previous.samples)
      ? previous.samples.filter(Number.isFinite).slice(-20)
      : [],
    outcomes: Array.isArray(previous.outcomes)
      ? previous.outcomes.map(Boolean).slice(-20)
      : [],
  };
}

export function applyProbeResult(record, result, health) {
  record.lastCheckedAt = result.checkedAt ?? new Date().toISOString();
  const success = result.success === true;
  record.outcomes.push(success);
  record.outcomes = record.outcomes.slice(-Math.max(2, Number(health.historySize ?? 12)));

  if (success) {
    if (Number.isFinite(result.rttMs)) {
      record.samples.push(result.rttMs);
      record.samples = record.samples.slice(-Math.max(2, Number(health.historySize ?? 12)));
      record.rttMs = Math.round(average(record.samples));
      record.jitterMs = Math.round(standardDeviation(record.samples));
    }
    record.consecutiveSuccesses += 1;
    record.consecutiveFailures = 0;
    record.lastError = null;
    record.recentFailurePenalty = Math.max(
      0,
      record.recentFailurePenalty - Number(health.failurePenaltyRecovery ?? 25),
    );
    if (record.consecutiveSuccesses >= Number(health.recoveryThreshold ?? 2)) {
      record.healthy = true;
    }
  } else {
    record.consecutiveFailures += 1;
    record.consecutiveSuccesses = 0;
    record.lastError = result.error || 'PROBE_FAILED';
    record.recentFailurePenalty = Math.min(
      Number(health.maxFailurePenalty ?? 1000),
      record.recentFailurePenalty + Number(health.failurePenaltyStep ?? 120),
    );
    if (record.consecutiveFailures >= Number(health.failureThreshold ?? 2)) {
      record.healthy = false;
    }
  }

  const failed = record.outcomes.filter((value) => !value).length;
  record.failureRate = record.outcomes.length ? failed / record.outcomes.length : 1;
  return record;
}

export function scoreRecord(record, health = {}) {
  const rtt = Number.isFinite(record.rttMs) ? record.rttMs : 50_000;
  const jitterWeight = Number(health.jitterWeight ?? 1.5);
  const lossWeight = Number(health.lossWeight ?? 1200);
  const loadWeight = Number(health.loadWeight ?? 900);
  const costWeight = Number(health.costWeight ?? 100);
  const load = clamp01(record.node.load ?? 0);
  const cost = Math.max(0, Number(record.node.cost ?? 1) - 1);
  return rtt +
    finiteOrZero(record.jitterMs) * jitterWeight +
    clamp01(record.failureRate) * lossWeight +
    load * loadWeight +
    cost * costWeight +
    Math.max(0, Number(record.recentFailurePenalty ?? 0));
}

export function eligibleRecords({ pool, state, protocol, forNewAssignment = true }) {
  const maxRtt = Number(pool.maxRttMs ?? 5000);
  return pool.nodes
    .map((node) => state.get(node.id))
    .filter(Boolean)
    .filter((record) => record.node.enabled !== false)
    .filter((record) => record.maintenance !== 'offline')
    .filter((record) => !forNewAssignment || record.maintenance !== 'draining')
    .filter((record) => !protocol || record.node.protocols?.includes(protocol))
    .filter((record) => record.healthy)
    .filter((record) => record.rttMs == null || record.rttMs <= maxRtt);
}

export function selectRoute({ config, state, sticky, clientId, poolId, protocol, now = Date.now() }) {
  const pool = config.pools.find((candidate) => candidate.id === poolId);
  if (!pool) return { error: 'POOL_NOT_FOUND', status: 404 };
  const key = `${clientId}:${poolId}:${protocol || '*'}`;
  const existing = sticky.get(key);

  if (existing && existing.expiresAt > now) {
    const current = state.get(existing.nodeId);
    const currentAllowed = current &&
      current.node.enabled !== false &&
      current.maintenance !== 'offline' &&
      current.healthy &&
      (!protocol || current.node.protocols?.includes(protocol));
    if (currentAllowed) {
      existing.expiresAt = now + Number(config.health.stickyTtlMs ?? 1_800_000);
      return selectedPayload(pool, current, true);
    }
  }

  const candidates = eligibleRecords({ pool, state, protocol, forNewAssignment: true })
    .sort((a, b) => scoreRecord(a, config.health) - scoreRecord(b, config.health));
  if (!candidates.length) {
    return { error: 'NO_HEALTHY_NODE', status: 503 };
  }

  const chosen = candidates[0];
  sticky.set(key, {
    nodeId: chosen.node.id,
    expiresAt: now + Number(config.health.stickyTtlMs ?? 1_800_000),
  });
  return selectedPayload(pool, chosen, false);
}

export function selectedPayload(pool, record, stickyHit) {
  return {
    poolId: pool.id,
    nodeId: record.node.id,
    endpoint: record.node.endpoint,
    protocols: record.node.protocols || [],
    countryCode: record.node.countryCode || '',
    rttMs: record.rttMs,
    jitterMs: record.jitterMs,
    failureRate: record.failureRate,
    score: Math.round(scoreRecord(record, {})),
    healthy: record.healthy,
    maintenance: record.maintenance,
    sticky: stickyHit,
    profileRef: record.node.profileRef || null,
  };
}

export function setMaintenance(record, mode) {
  record.maintenance = normalizeMaintenance(mode);
  if (record.maintenance === 'offline') record.healthy = false;
  return record;
}

export function serializeState(state, sticky) {
  return {
    version: 1,
    savedAt: new Date().toISOString(),
    nodes: Object.fromEntries([...state.entries()].map(([id, record]) => [id, {
      maintenance: record.maintenance,
      healthy: record.healthy,
      rttMs: record.rttMs,
      jitterMs: record.jitterMs,
      failureRate: record.failureRate,
      recentFailurePenalty: record.recentFailurePenalty,
      consecutiveFailures: record.consecutiveFailures,
      consecutiveSuccesses: record.consecutiveSuccesses,
      lastCheckedAt: record.lastCheckedAt,
      lastError: record.lastError,
      samples: record.samples,
      outcomes: record.outcomes,
    }])),
    sticky: Object.fromEntries(sticky),
  };
}

export function loadPersistentState(filePath) {
  if (!filePath) return { nodes: {}, sticky: {} };
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return {
      nodes: parsed?.nodes && typeof parsed.nodes === 'object' ? parsed.nodes : {},
      sticky: parsed?.sticky && typeof parsed.sticky === 'object' ? parsed.sticky : {},
    };
  } catch (error) {
    if (error?.code === 'ENOENT') return { nodes: {}, sticky: {} };
    throw error;
  }
}

export function savePersistentState(filePath, state, sticky) {
  if (!filePath) return;
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(serializeState(state, sticky), null, 2), { mode: 0o600 });
  fs.renameSync(temporary, filePath);
}

export function restoreSticky(rawSticky, now = Date.now()) {
  const restored = new Map();
  for (const [key, value] of Object.entries(rawSticky ?? {})) {
    if (value && typeof value.nodeId === 'string' && Number(value.expiresAt) > now) {
      restored.set(key, { nodeId: value.nodeId, expiresAt: Number(value.expiresAt) });
    }
  }
  return restored;
}

function normalizeMaintenance(value) {
  if (!['online', 'draining', 'offline'].includes(value)) {
    throw new Error(`invalid maintenance state: ${value}`);
  }
  return value;
}

function clamp01(value) {
  return Math.max(0, Math.min(1, Number(value) || 0));
}

function finiteOrNull(value) {
  return Number.isFinite(Number(value)) ? Number(value) : null;
}

function finiteOrZero(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}
