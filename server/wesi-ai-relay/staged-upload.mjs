import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const STAGED_UPLOAD_MIME = 'application/x-wesi-upload-ref';
export const STAGED_CHUNK_BYTES = 1024 * 1024;
export const STAGED_MAX_FILE_BYTES = 256 * 1024 * 1024;
export const STAGED_TTL_MS = 60 * 60 * 1000;
export const STAGED_MAX_ACTIVE_BYTES = 1024 * 1024 * 1024;
export const STAGED_MAX_ACTIVE_UPLOADS = 32;

const ROOT = process.env.WESI_RELAY_UPLOAD_DIR || path.join(os.tmpdir(), 'wesi-ai-staged-uploads-v1');
const ID_RE = /^[A-Za-z0-9_-]{20,96}$/;
const MIME_RE = /^[a-z0-9!#$&^_.+\-]+\/[a-z0-9!#$&^_.+\-]+$/i;

function ensureRoot() {
  fs.mkdirSync(ROOT, {recursive: true, mode: 0o700});
}

function safeName(raw) {
  const cleaned = String(raw || 'file').replace(/[\\/\0-\x1f\x7f]/g, '_').trim();
  return (cleaned || 'file').slice(-180);
}

function safeId(raw) {
  const id = String(raw || '').trim();
  if (!ID_RE.test(id)) throw new Error('WAI_UPLOAD_INVALID');
  return id;
}

function uploadDir(id) {
  return path.join(ROOT, safeId(id));
}

function metaPath(id) {
  return path.join(uploadDir(id), 'meta.json');
}

function chunkPath(id, index) {
  return path.join(uploadDir(id), `chunk-${String(index).padStart(4, '0')}.bin`);
}

function payloadPath(id) {
  return path.join(uploadDir(id), 'payload.bin');
}

function decodeBase64Strict(raw) {
  const value = String(raw || '').trim();
  if (!value || !/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) {
    throw new Error('WAI_UPLOAD_BAD_CHUNK');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.toString('base64').replace(/=+$/, '') !== value.replace(/=+$/, '')) {
    throw new Error('WAI_UPLOAD_BAD_CHUNK');
  }
  return bytes;
}

function writeMeta(meta) {
  fs.writeFileSync(metaPath(meta.id), JSON.stringify(meta), {mode: 0o600});
}

function loadMeta(rawId, {allowExpired = false} = {}) {
  const id = safeId(rawId);
  let meta;
  try {
    meta = JSON.parse(fs.readFileSync(metaPath(id), 'utf8'));
  } catch {
    throw new Error('WAI_UPLOAD_NOT_FOUND');
  }
  if (!meta || meta.id !== id || !ID_RE.test(String(meta.cap || ''))) {
    throw new Error('WAI_UPLOAD_INVALID');
  }
  if (!allowExpired && Number(meta.expiresAt || 0) <= Date.now()) {
    try { fs.rmSync(uploadDir(id), {recursive: true, force: true}); } catch {}
    throw new Error('WAI_UPLOAD_EXPIRED');
  }
  return meta;
}

export function cleanupExpiredStagedUploads(now = Date.now()) {
  ensureRoot();
  let entries = [];
  try { entries = fs.readdirSync(ROOT, {withFileTypes: true}); } catch { return; }
  for (const entry of entries) {
    if (!entry.isDirectory() || !ID_RE.test(entry.name)) continue;
    try {
      const meta = loadMeta(entry.name, {allowExpired: true});
      if (Number(meta.expiresAt || 0) <= now) {
        fs.rmSync(uploadDir(entry.name), {recursive: true, force: true});
      }
    } catch {
      try { fs.rmSync(uploadDir(entry.name), {recursive: true, force: true}); } catch {}
    }
  }
}

function activeStagedBudget(now = Date.now()) {
  ensureRoot();
  let entries = [];
  try { entries = fs.readdirSync(ROOT, {withFileTypes: true}); } catch { return {uploads: 0, bytes: 0}; }
  let uploads = 0;
  let bytes = 0;
  for (const entry of entries) {
    if (!entry.isDirectory() || !ID_RE.test(entry.name)) continue;
    try {
      const meta = loadMeta(entry.name, {allowExpired: true});
      if (Number(meta.expiresAt || 0) <= now) {
        fs.rmSync(uploadDir(entry.name), {recursive: true, force: true});
        continue;
      }
      const declared = Number(meta.byteSize || 0);
      if (!Number.isSafeInteger(declared) || declared <= 0 || declared > STAGED_MAX_FILE_BYTES) {
        fs.rmSync(uploadDir(entry.name), {recursive: true, force: true});
        continue;
      }
      uploads += 1;
      bytes += declared;
    } catch {
      try { fs.rmSync(uploadDir(entry.name), {recursive: true, force: true}); } catch {}
    }
  }
  return {uploads, bytes};
}

export function startStagedUpload(input = {}) {
  cleanupExpiredStagedUploads();
  const name = safeName(input.name);
  const mimeType = String(input.mimeType || 'application/octet-stream').trim().toLowerCase();
  const byteSize = Number(input.byteSize || 0);
  if (!MIME_RE.test(mimeType) || mimeType.length > 120) throw new Error('WAI_UPLOAD_INVALID');
  if (!Number.isSafeInteger(byteSize) || byteSize <= 0 || byteSize > STAGED_MAX_FILE_BYTES) {
    throw new Error('WAI_UPLOAD_TOO_LARGE');
  }
  const budget = activeStagedBudget();
if (budget.uploads >= STAGED_MAX_ACTIVE_UPLOADS || budget.bytes + byteSize > STAGED_MAX_ACTIVE_BYTES) {
  throw new Error('WAI_UPLOAD_CAPACITY');
}
  const id = crypto.randomBytes(24).toString('base64url');
  const cap = crypto.randomBytes(24).toString('base64url');
  const chunkSize = STAGED_CHUNK_BYTES;
  const chunkCount = Math.ceil(byteSize / chunkSize);
  const createdAt = Date.now();
  const meta = {
    v: 1,
    id,
    cap,
    name,
    mimeType,
    byteSize,
    chunkSize,
    chunkCount,
    createdAt,
    expiresAt: createdAt + STAGED_TTL_MS,
    status: 'receiving',
  };
  fs.mkdirSync(uploadDir(id), {recursive: false, mode: 0o700});
  writeMeta(meta);
  return {
    id,
    chunkSize,
    chunkCount,
    expiresAt: new Date(meta.expiresAt).toISOString(),
  };
}

export function putStagedChunk(input = {}) {
  const meta = loadMeta(input.uploadId);
  if (meta.status !== 'receiving') throw new Error('WAI_UPLOAD_ALREADY_COMPLETE');
  const index = Number(input.index);
  if (!Number.isSafeInteger(index) || index < 0 || index >= meta.chunkCount) {
    throw new Error('WAI_UPLOAD_BAD_CHUNK');
  }
  const bytes = decodeBase64Strict(input.dataBase64);
  const offset = index * meta.chunkSize;
  const expected = Math.min(meta.chunkSize, meta.byteSize - offset);
  if (bytes.length !== expected) throw new Error('WAI_UPLOAD_CHUNK_MISMATCH');
  fs.writeFileSync(chunkPath(meta.id, index), bytes, {mode: 0o600});
  return {id: meta.id, index, byteSize: bytes.length};
}

export async function completeStagedUpload(input = {}) {
  const meta = loadMeta(input.uploadId);
  if (meta.status === 'complete') return transportFor(meta);
  if (meta.status !== 'receiving') throw new Error('WAI_UPLOAD_INVALID');

  let total = 0;
  for (let index = 0; index < meta.chunkCount; index++) {
    let stat;
    try { stat = fs.statSync(chunkPath(meta.id, index)); } catch { throw new Error('WAI_UPLOAD_INCOMPLETE'); }
    const expected = Math.min(meta.chunkSize, meta.byteSize - index * meta.chunkSize);
    if (!stat.isFile() || stat.size !== expected) throw new Error('WAI_UPLOAD_CHUNK_MISMATCH');
    total += stat.size;
  }
  if (total !== meta.byteSize) throw new Error('WAI_UPLOAD_CHUNK_MISMATCH');

  const temp = payloadPath(meta.id) + '.tmp';
  await fs.promises.writeFile(temp, Buffer.alloc(0), {mode: 0o600});
  try {
    for (let index = 0; index < meta.chunkCount; index++) {
      const bytes = await fs.promises.readFile(chunkPath(meta.id, index));
      await fs.promises.appendFile(temp, bytes);
    }
    const stat = await fs.promises.stat(temp);
    if (stat.size !== meta.byteSize) throw new Error('WAI_UPLOAD_CHUNK_MISMATCH');
    await fs.promises.rename(temp, payloadPath(meta.id));
    for (let index = 0; index < meta.chunkCount; index++) {
      await fs.promises.rm(chunkPath(meta.id, index), {force: true});
    }
    meta.status = 'complete';
    meta.completedAt = Date.now();
    meta.expiresAt = Date.now() + STAGED_TTL_MS;
    writeMeta(meta);
    return transportFor(meta);
  } catch (error) {
    try { await fs.promises.rm(temp, {force: true}); } catch {}
    throw error;
  }
}

function transportFor(meta) {
  const ref = Buffer.from(JSON.stringify({v: 1, id: meta.id, cap: meta.cap}), 'utf8');
  return {
    name: meta.name,
    mimeType: STAGED_UPLOAD_MIME,
    byteSize: ref.length,
    dataBase64: ref.toString('base64'),
  };
}

export function resolveStagedAttachment(item) {
  if (!item || item.mimeType !== STAGED_UPLOAD_MIME) return null;
  let ref;
  try { ref = JSON.parse(Buffer.from(item.bytes || []).toString('utf8')); } catch { throw new Error('WAI_UPLOAD_REF_INVALID'); }
  if (!ref || ref.v !== 1) throw new Error('WAI_UPLOAD_REF_INVALID');
  const meta = loadMeta(ref.id);
  if (meta.status !== 'complete' || String(ref.cap || '') !== String(meta.cap || '')) {
    throw new Error('WAI_UPLOAD_REF_INVALID');
  }
  const filePath = payloadPath(meta.id);
  let stat;
  try { stat = fs.statSync(filePath); } catch { throw new Error('WAI_UPLOAD_EXPIRED'); }
  if (!stat.isFile() || stat.size !== meta.byteSize) throw new Error('WAI_UPLOAD_CHUNK_MISMATCH');
  meta.expiresAt = Date.now() + STAGED_TTL_MS;
  writeMeta(meta);
  return {
    name: meta.name,
    mimeType: meta.mimeType,
    byteSize: meta.byteSize,
    extension: meta.name.toLowerCase().includes('.') ? meta.name.toLowerCase().split('.').pop() : '',
    filePath,
    staged: true,
    uploadId: meta.id,
  };
}

export function cancelStagedUpload(input = {}) {
  const id = safeId(input.uploadId);
  try { fs.rmSync(uploadDir(id), {recursive: true, force: true}); } catch {}
  return {id, cancelled: true};
}
