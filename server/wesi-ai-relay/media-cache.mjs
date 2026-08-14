import crypto from 'node:crypto';

const DEFAULT_TTL_MS = 10 * 60 * 1000;
const MAX_TOTAL_BYTES = 256 * 1024 * 1024;
const MAX_ITEM_BYTES = 128 * 1024 * 1024;
const MAX_ITEMS = 32;

const items = new Map();
let totalBytes = 0;

function prune(now = Date.now()) {
  for (const [id, item] of items) {
    if (item.expiresAt <= now) {
      totalBytes -= item.bytes.length;
      items.delete(id);
    }
  }
  while (items.size > MAX_ITEMS || totalBytes > MAX_TOTAL_BYTES) {
    const oldest = items.keys().next();
    if (oldest.done) break;
    const item = items.get(oldest.value);
    if (item) totalBytes -= item.bytes.length;
    items.delete(oldest.value);
  }
}

export function putMedia(media, {ttlMs = DEFAULT_TTL_MS} = {}) {
  prune();
  const encoded = String(media?.data || '');
  if (!encoded || !/^[A-Za-z0-9+/=]+$/.test(encoded)) {
    return {ok: false, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  let bytes;
  try {
    bytes = Buffer.from(encoded, 'base64');
  } catch {
    return {ok: false, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  if (!bytes.length || bytes.length > MAX_ITEM_BYTES) {
    return {ok: false, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  const declared = Number(media?.byteSize || 0);
  if (declared && declared !== bytes.length) {
    return {ok: false, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  const id = crypto.randomBytes(24).toString('base64url');
  const item = {
    bytes,
    mimeType: String(media?.mimeType || 'application/octet-stream').slice(0, 120),
    kind: String(media?.kind || 'media').slice(0, 40),
    createdAt: Date.now(),
    expiresAt: Date.now() + Math.max(30_000, Math.min(Number(ttlMs) || DEFAULT_TTL_MS, 30 * 60 * 1000)),
  };
  items.set(id, item);
  totalBytes += bytes.length;
  prune();
  if (!items.has(id)) return {ok: false, code: 'WAI_RELAY_MEDIA_CAPACITY'};
  return {
    ok: true,
    artifactId: id,
    mimeType: item.mimeType,
    kind: item.kind,
    byteSize: bytes.length,
    expiresAt: new Date(item.expiresAt).toISOString(),
  };
}

/// Atomically removes and returns one media artifact. Main Server is expected
/// to persist it immediately. A second fetch returns null, which makes a
/// captured signed fetch useless even beyond the request-id replay guard.
export function takeMedia(id) {
  prune();
  const key = String(id || '');
  if (!/^[A-Za-z0-9_-]{20,80}$/.test(key)) return null;
  const item = items.get(key);
  if (!item) return null;
  items.delete(key);
  totalBytes -= item.bytes.length;
  return item;
}

export function cacheStats() {
  prune();
  return {items: items.size, totalBytes};
}

export function clearMediaCacheForTests() {
  items.clear();
  totalBytes = 0;
}
