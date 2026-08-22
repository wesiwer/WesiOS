import { scoreRecord } from './route-core.mjs';

export const DEFAULT_PROTOCOL_PRIORITY = Object.freeze([
  'vless-reality',
  'hysteria2',
  'tuic',
  'vmess',
  'trojan',
  'shadowsocks',
  'amneziawg',
  'wireguard',
]);

export function selectAutomaticRoute({
  config,
  state,
  sticky,
  clientId,
  preferredPoolIds = null,
  protocolPriority = null,
  now = Date.now(),
}) {
  const priorities = Array.isArray(protocolPriority) && protocolPriority.length
    ? protocolPriority.map(String)
    : Array.isArray(config.auto?.protocolPriority) && config.auto.protocolPriority.length
      ? config.auto.protocolPriority.map(String)
      : DEFAULT_PROTOCOL_PRIORITY;

  const orderedPools = orderPools(config, preferredPoolIds);
  const stickyKey = `${clientId}:auto`;
  const existing = sticky.get(stickyKey);

  if (existing && Number(existing.expiresAt) > now) {
    const record = state.get(existing.nodeId);
    const poolAllowed = orderedPools.some((pool) => pool.id === existing.poolId);
    if (poolAllowed && record && isUsable(record, existing.protocol, true)) {
      existing.expiresAt = now + Number(config.health?.stickyTtlMs ?? 1_800_000);
      return payload(record, existing.poolId, existing.protocol, true);
    }
  }

  const candidates = [];
  for (let poolIndex = 0; poolIndex < orderedPools.length; poolIndex += 1) {
    const pool = orderedPools[poolIndex];
    for (let protocolIndex = 0; protocolIndex < priorities.length; protocolIndex += 1) {
      const protocol = priorities[protocolIndex];
      for (const node of pool.nodes ?? []) {
        const record = state.get(node.id);
        if (!record || !isUsable(record, protocol, false)) continue;
        if (Number.isFinite(record.rttMs) && record.rttMs > Number(pool.maxRttMs ?? 5000)) continue;
        candidates.push({
          pool,
          record,
          protocol,
          score: scoreRecord(record, config.health ?? {}) +
            poolIndex * Number(config.auto?.poolPenalty ?? 400) +
            protocolIndex * Number(config.auto?.protocolPenalty ?? 120),
        });
      }
    }
  }

  candidates.sort((a, b) => a.score - b.score);
  const chosen = candidates[0];
  if (!chosen) return { error: 'NO_AUTOMATIC_ROUTE', status: 503 };

  sticky.set(stickyKey, {
    nodeId: chosen.record.node.id,
    poolId: chosen.pool.id,
    protocol: chosen.protocol,
    expiresAt: now + Number(config.health?.stickyTtlMs ?? 1_800_000),
  });
  return payload(chosen.record, chosen.pool.id, chosen.protocol, false);
}

function orderPools(config, preferredPoolIds) {
  const pools = [...(config.pools ?? [])];
  const configured = Array.isArray(config.auto?.poolPriority)
    ? config.auto.poolPriority.map(String)
    : [];
  const preferred = Array.isArray(preferredPoolIds)
    ? preferredPoolIds.map(String)
    : [];
  const explicit = [...new Set([...preferred, ...configured])];
  const includeUnlisted = config.auto?.includeUnlistedPools === true;
  const allowed = explicit.length && !includeUnlisted
    ? pools.filter((pool) => explicit.includes(pool.id))
    : pools;
  const rank = new Map(explicit.map((id, index) => [id, index]));
  return allowed.sort((a, b) => {
    const ar = rank.has(a.id) ? rank.get(a.id) : 10_000;
    const br = rank.has(b.id) ? rank.get(b.id) : 10_000;
    if (ar !== br) return ar - br;
    return Number(a.cost ?? 1) - Number(b.cost ?? 1);
  });
}

function isUsable(record, protocol, allowDrainingSticky) {
  return record.node.enabled !== false &&
    record.maintenance !== 'offline' &&
    (allowDrainingSticky || record.maintenance !== 'draining') &&
    record.healthy === true &&
    Array.isArray(record.node.protocols) &&
    record.node.protocols.includes(protocol);
}

function payload(record, poolId, protocol, stickyHit) {
  return {
    mode: 'automatic',
    poolId,
    nodeId: record.node.id,
    endpoint: record.node.endpoint,
    countryCode: record.node.countryCode || '',
    protocol,
    engine: 'auto',
    profileRef: record.node.profileRef || null,
    rttMs: record.rttMs,
    jitterMs: record.jitterMs,
    failureRate: record.failureRate,
    healthy: record.healthy,
    sticky: stickyHit,
  };
}
