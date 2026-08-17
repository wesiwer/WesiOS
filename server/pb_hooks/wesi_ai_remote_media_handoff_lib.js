const CHUNK_BYTES = 256 * 1024;
const MAX_FILE_BYTES = 1024 * 1024 * 1024;
const MAX_CHUNKS = Math.ceil(MAX_FILE_BYTES / CHUNK_BYTES);
const HANDOFF_TTL_MS = 2 * 60 * 60 * 1000;

const ID_RE = /^[A-Za-z0-9._:-]{1,128}$/;
const HANDOFF_RE = /^wrm_[A-Za-z0-9_-]{20,80}$/;
const WORKER_RE = /^[A-Za-z0-9_-]{20,96}$/;
const SHA_RE = /^[a-f0-9]{64}$/;
const MIME_RE = /^[a-z0-9!#$&^_.+\-]+\/[a-z0-9!#$&^_.+\-]+$/i;

const ALLOWED_MIME = new Set([
  'image/png',
  'image/jpeg',
  'image/webp',
  'audio/mpeg',
  'audio/mp3',
  'audio/wav',
  'audio/x-wav',
  'audio/flac',
  'audio/ogg',
  'audio/mp4',
  'audio/aac',
  'video/mp4',
  'video/webm',
  'video/quicktime',
  'video/x-matroska',
  'application/zip',
  'text/plain',
  'text/vtt',
  'application/x-subrip',
]);

function fail(code) {
  throw new Error(code);
}

function cleanName(value) {
  let name = String(value == null ? '' : value)
    .replace(/[\\/\x00-\x1f\x7f]/g, '_')
    .trim();
  if (!name) name = 'media.bin';
  if (name.length > 180) name = name.slice(name.length - 180);
  return name;
}

function normalizeMime(value) {
  const mime = String(value == null ? '' : value)
    .split(';')[0]
    .trim()
    .toLowerCase();
  if (!MIME_RE.test(mime) || mime.length > 120 || !ALLOWED_MIME.has(mime)) {
    fail('WRM_MIME_FORBIDDEN');
  }
  return mime;
}

function validateJobId(value) {
  const id = String(value == null ? '' : value).trim();
  if (!ID_RE.test(id)) fail('WRM_BAD_JOB_ID');
  return id;
}

function validateHandoffId(value) {
  const id = String(value == null ? '' : value).trim();
  if (!HANDOFF_RE.test(id)) fail('WRM_BAD_HANDOFF_ID');
  return id;
}

function validateSha256(value) {
  const digest = String(value == null ? '' : value).trim().toLowerCase();
  if (!SHA_RE.test(digest)) fail('WRM_BAD_SHA256');
  return digest;
}

function normalizeFileMeta(raw, options = {}) {
  const input = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const maxBytes = Math.min(
    Number.isSafeInteger(options.maxBytes) && options.maxBytes > 0
      ? options.maxBytes
      : MAX_FILE_BYTES,
    MAX_FILE_BYTES,
  );
  const byteSize = Number(input.byteSize || 0);
  if (!Number.isSafeInteger(byteSize) || byteSize <= 0 || byteSize > maxBytes) {
    fail('WRM_FILE_SIZE_INVALID');
  }
  const chunkCount = Math.ceil(byteSize / CHUNK_BYTES);
  if (chunkCount <= 0 || chunkCount > MAX_CHUNKS) fail('WRM_FILE_SIZE_INVALID');
  return {
    name: cleanName(input.name),
    mimeType: normalizeMime(input.mimeType),
    byteSize,
    sha256: validateSha256(input.sha256),
    chunkSize: CHUNK_BYTES,
    chunkCount,
  };
}

function expectedChunkBytes(meta, rawIndex) {
  if (!meta || typeof meta !== 'object') fail('WRM_BAD_FILE_META');
  const byteSize = Number(meta.byteSize || 0);
  const chunkSize = Number(meta.chunkSize || 0);
  const chunkCount = Number(meta.chunkCount || 0);
  const index = Number(rawIndex);
  if (!Number.isSafeInteger(byteSize) || byteSize <= 0 || byteSize > MAX_FILE_BYTES ||
      chunkSize !== CHUNK_BYTES || !Number.isSafeInteger(chunkCount) ||
      chunkCount !== Math.ceil(byteSize / chunkSize) || chunkCount > MAX_CHUNKS ||
      !Number.isSafeInteger(index) || index < 0 || index >= chunkCount) {
    fail('WRM_BAD_CHUNK');
  }
  return Math.min(chunkSize, byteSize - index * chunkSize);
}

function bindWorker(boundWorkerId, authenticatedWorkerId, hasAssignment) {
  const authenticated = String(authenticatedWorkerId || '').trim();
  const bound = String(boundWorkerId || '').trim();
  if (!WORKER_RE.test(authenticated) || hasAssignment !== true) {
    fail('WRM_WORKER_NOT_ASSIGNED');
  }
  if (bound && (!WORKER_RE.test(bound) || bound !== authenticated)) {
    fail('WRM_WORKER_MISMATCH');
  }
  return authenticated;
}

function base64Encode(bytes) {
  const input = Array.from(bytes || [], (value) => Number(value) & 255);
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < input.length; i += 3) {
    const a = input[i];
    const hasB = i + 1 < input.length;
    const hasC = i + 2 < input.length;
    const b = hasB ? input[i + 1] : 0;
    const c = hasC ? input[i + 2] : 0;
    out += alphabet[(a >> 2) & 63];
    out += alphabet[((a & 3) << 4) | ((b >> 4) & 15)];
    out += hasB ? alphabet[((b & 15) << 2) | ((c >> 6) & 3)] : '=';
    out += hasC ? alphabet[c & 63] : '=';
  }
  return out;
}

function base64Decode(value, maxBytes = CHUNK_BYTES) {
  const text = String(value == null ? '' : value).trim();
  if (!text || text.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) {
    fail('WRM_BAD_BASE64');
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const reverse = {};
  for (let i = 0; i < alphabet.length; i++) reverse[alphabet[i]] = i;
  const padding = text.endsWith('==') ? 2 : text.endsWith('=') ? 1 : 0;
  const expected = (text.length / 4) * 3 - padding;
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0 || expected <= 0 || expected > maxBytes) {
    fail('WRM_BAD_BASE64');
  }
  const out = [];
  for (let i = 0; i < text.length; i += 4) {
    const c0 = reverse[text[i]];
    const c1 = reverse[text[i + 1]];
    const c2 = text[i + 2] === '=' ? 0 : reverse[text[i + 2]];
    const c3 = text[i + 3] === '=' ? 0 : reverse[text[i + 3]];
    if ([c0, c1, c2, c3].some((value) => value == null)) fail('WRM_BAD_BASE64');
    const packed = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;
    out.push((packed >> 16) & 255);
    if (text[i + 2] !== '=') out.push((packed >> 8) & 255);
    if (text[i + 3] !== '=') out.push(packed & 255);
  }
  if (out.length !== expected || base64Encode(out) !== text) fail('WRM_BAD_BASE64');
  return out;
}

module.exports = {
  CHUNK_BYTES,
  MAX_FILE_BYTES,
  MAX_CHUNKS,
  HANDOFF_TTL_MS,
  cleanName,
  normalizeMime,
  validateJobId,
  validateHandoffId,
  validateSha256,
  normalizeFileMeta,
  expectedChunkBytes,
  bindWorker,
  base64Encode,
  base64Decode,
};
