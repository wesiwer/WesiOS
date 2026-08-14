import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const VAULT_DIR = process.env.WESI_CONNECTOR_VAULT_DIR || '/var/lib/wesi-connectors';
const VAULT_FILE = path.join(VAULT_DIR, 'credentials.json');

function masterKey() {
  const raw = String(process.env.WESI_CONNECTOR_MASTER_KEY || '');
  if (raw.length < 32) {
    const error = new Error('CONNECTOR_MASTER_KEY_NOT_CONFIGURED');
    error.code = 'CONNECTOR_MASTER_KEY_NOT_CONFIGURED';
    throw error;
  }
  return crypto.createHash('sha256').update(raw, 'utf8').digest();
}

function readStore() {
  try {
    const parsed = JSON.parse(fs.readFileSync(VAULT_FILE, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (error) {
    if (error && error.code === 'ENOENT') return {};
    throw error;
  }
}

function writeStore(store) {
  fs.mkdirSync(VAULT_DIR, {recursive: true, mode: 0o700});
  const tmp = `${VAULT_FILE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store), {mode: 0o600});
  fs.renameSync(tmp, VAULT_FILE);
  fs.chmodSync(VAULT_FILE, 0o600);
}

function seal(value, aad) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', masterKey(), iv);
  cipher.setAAD(Buffer.from(aad));
  const encrypted = Buffer.concat([cipher.update(String(value), 'utf8'), cipher.final()]);
  return {
    v: 1,
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    data: encrypted.toString('base64'),
  };
}

function open(box, aad) {
  if (!box || box.v !== 1) throw new Error('INVALID_VAULT_RECORD');
  const decipher = crypto.createDecipheriv('aes-256-gcm', masterKey(), Buffer.from(box.iv, 'base64'));
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(Buffer.from(box.tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(box.data, 'base64')), decipher.final()]).toString('utf8');
}

function keyFor(ownerId, connector) {
  return `${String(ownerId)}:${String(connector)}`;
}

export function putCredential(ownerId, connector, secret, metadata = {}) {
  const key = keyFor(ownerId, connector);
  const store = readStore();
  store[key] = {
    connector,
    ownerId: String(ownerId),
    secret: seal(secret, key),
    metadata,
    updatedAt: new Date().toISOString(),
  };
  writeStore(store);
}

export function getCredential(ownerId, connector) {
  const key = keyFor(ownerId, connector);
  const record = readStore()[key];
  if (!record) return null;
  return {secret: open(record.secret, key), metadata: record.metadata || {}, updatedAt: record.updatedAt || null};
}

export function deleteCredential(ownerId, connector) {
  const key = keyFor(ownerId, connector);
  const store = readStore();
  if (!store[key]) return false;
  delete store[key];
  writeStore(store);
  return true;
}

export function listCredentials(ownerId) {
  const prefix = `${String(ownerId)}:`;
  return Object.entries(readStore())
    .filter(([key]) => key.startsWith(prefix))
    .map(([, value]) => ({connector: value.connector, metadata: value.metadata || {}, updatedAt: value.updatedAt || null}));
}
