const TIER_RANK = Object.freeze({fast: 1, pro: 2, ultra: 3});
const health = new Map();

const RATE_LIMIT_BASE_MS = 60_000;
const RATE_LIMIT_MAX_MS = 6 * 60 * 60 * 1000;
const TRANSIENT_BASE_MS = 15_000;
const TRANSIENT_MAX_MS = 5 * 60 * 1000;
const AUTH_BASE_MS = 15 * 60 * 1000;
const AUTH_MAX_MS = 24 * 60 * 60 * 1000;

export function normalizeWesiTier(value) {
  const tier = String(value || '').trim().toLowerCase();
  return Object.hasOwn(TIER_RANK, tier) ? tier : null;
}

export function tierRank(value) {
  const tier = normalizeWesiTier(value);
  return tier ? TIER_RANK[tier] : 0;
}

function candidateId(candidate) {
  const explicit = String(candidate?.id || '').trim();
  if (explicit) return explicit;
  const provider = String(candidate?.provider || 'provider').trim();
  const model = String(candidate?.model || 'model').trim();
  const slot = String(candidate?.credentialSlot || 'default').trim();
  return `${provider}:${model}:${slot}`;
}

export function assertCandidateAllowed(tier, candidate, {allowLower = false} = {}) {
  const routeTier = normalizeWesiTier(tier);
  const candidateTier = normalizeWesiTier(candidate?.tier);
  if (!routeTier || !candidateTier) {
    throw new Error('WAI_PROVIDER_TIER_INVALID');
  }
  const routeRank = TIER_RANK[routeTier];
  const candidateRank = TIER_RANK[candidateTier];
  if (candidateRank > routeRank || (!allowLower && candidateRank !== routeRank)) {
    throw new Error('WAI_PROVIDER_TIER_VIOLATION');
  }
  return true;
}

export function geminiKeySlots(primaryKey, secrets = {}) {
  const raw = [
    ['primary', primaryKey],
    ['secondary-2', secrets.GEMINI_API_KEY_2],
    ['secondary-3', secrets.GEMINI_API_KEY_3],
    ['secondary-4', secrets.GEMINI_API_KEY_4],
    ['secondary-5', secrets.GEMINI_API_KEY_5],
  ];
  const seen = new Set();
  const result = [];
  for (const [slot, value] of raw) {
    const key = String(value || '').trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push({slot, key});
  }
  return result;
}

export function isRetryableProviderResult(result) {
  if (!result || result.ok) return false;
  const status = Number(result.status || 0);
  const code = String(result.code || '');
  if (code === 'WAI_PROVIDER_NOT_CONFIGURED') return true;
  if (status === 429 || status >= 500) return true;
  return new Set([
    'WAI_PROVIDER_RATE_LIMIT',
    'WAI_PROVIDER_UNAVAILABLE',
    'WAI_PROVIDER_TIMEOUT',
    'WAI_PROVIDER_REJECTED',
    'WAI_PROVIDER_AUTH_FAILED',
    'WAI_PROVIDER_POOL_COOLDOWN',
  ]).has(code);
}

function cooldownFor(result, failures) {
  const code = String(result?.code || '');
  const status = Number(result?.status || 0);
  const exponent = Math.max(0, Math.min(Number(failures || 1) - 1, 10));
  let base = TRANSIENT_BASE_MS;
  let max = TRANSIENT_MAX_MS;
  if (status === 429 || code === 'WAI_PROVIDER_RATE_LIMIT') {
    base = RATE_LIMIT_BASE_MS;
    max = RATE_LIMIT_MAX_MS;
  } else if (code === 'WAI_PROVIDER_AUTH_FAILED') {
    base = AUTH_BASE_MS;
    max = AUTH_MAX_MS;
  }
  const computed = Math.min(max, base * (2 ** exponent));
  const providerHint = Math.max(0, Number(result?.retryAfterMs || 0));
  return Math.max(computed, providerHint);
}

function stateFor(candidate) {
  return health.get(candidateId(candidate)) || {failures: 0, cooldownUntil: 0, lastCode: ''};
}

function noteResult(candidate, result, now) {
  const id = candidateId(candidate);
  if (result?.ok) {
    health.delete(id);
    return;
  }
  if (String(result?.code || '') === 'WAI_PROVIDER_NOT_CONFIGURED') return;
  if (!isRetryableProviderResult(result)) return;
  const previous = stateFor(candidate);
  const failures = previous.failures + 1;
  health.set(id, {
    failures,
    cooldownUntil: now + cooldownFor(result, failures),
    lastCode: String(result?.code || ''),
  });
}

export function providerCooldown(candidate, now = Date.now()) {
  const current = stateFor(candidate);
  const remainingMs = Math.max(0, current.cooldownUntil - Number(now || 0));
  return {
    cooling: remainingMs > 0,
    remainingMs,
    failures: current.failures,
    lastCode: current.lastCode,
  };
}

export function resetProviderFailoverState() {
  health.clear();
}

export async function runProviderFailover({
  tier,
  candidates,
  invoke,
  allowLower = false,
  now = () => Date.now(),
}) {
  const routeTier = normalizeWesiTier(tier);
  if (!routeTier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  if (!Array.isArray(candidates) || candidates.length === 0) {
    return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  }
  for (const candidate of candidates) assertCandidateAllowed(routeTier, candidate, {allowLower});

  let last = {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  let attempted = 0;
  let shortestCooldown = Number.POSITIVE_INFINITY;

  for (let index = 0; index < candidates.length; index++) {
    const candidate = candidates[index];
    const timestamp = Number(now());
    const cooldown = providerCooldown(candidate, timestamp);
    if (cooldown.cooling) {
      shortestCooldown = Math.min(shortestCooldown, cooldown.remainingMs);
      continue;
    }

    attempted += 1;
    let result;
    try {
      result = await invoke(candidate);
    } catch (error) {
      result = {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE'};
    }
    noteResult(candidate, result, Number(now()));

    if (result?.ok) {
      return {
        ...result,
        provider: result.provider || candidate.provider || null,
        model: result.model || candidate.model || null,
        failoverIndex: index,
      };
    }

    last = result || last;
    if (result?.emitted) return last;
    if (!isRetryableProviderResult(last)) return last;
  }

  if (attempted === 0 && Number.isFinite(shortestCooldown)) {
    return {
      ok: false,
      status: 429,
      code: 'WAI_PROVIDER_POOL_COOLDOWN',
      retryAfterMs: Math.ceil(shortestCooldown),
    };
  }
  return last;
}
