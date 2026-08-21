import {
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
  randomUUID,
} from 'node:crypto';

export class SecureChannelError extends Error {
  constructor(code, message, statusCode = 400) {
    super(message);
    this.name = 'SecureChannelError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class ReplayGuard {
  constructor({ now = () => Date.now(), ttlMs = 120_000, maxEntries = 10_000 } = {}) {
    this.now = now;
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
    this.entries = new Map();
  }

  consume(requestId, timestamp) {
    const now = this.now();
    if (!Number.isSafeInteger(timestamp) || Math.abs(now - timestamp) > this.ttlMs) {
      throw new SecureChannelError('STALE_ENVELOPE', 'Encrypted request timestamp is stale', 401);
    }
    this.#prune(now);
    if (this.entries.has(requestId)) {
      throw new SecureChannelError('REPLAY_DETECTED', 'Encrypted request was already processed', 409);
    }
    this.entries.set(requestId, now + this.ttlMs);
  }

  #prune(now) {
    for (const [id, expiresAt] of this.entries) {
      if (expiresAt <= now || this.entries.size >= this.maxEntries) {
        this.entries.delete(id);
      }
    }
  }
}

export function encryptEnvelope(payload, licenseKey, {
  requestId = randomUUID(),
  timestamp = Date.now(),
  direction = 'request',
  salt = randomBytes(16),
  nonce = randomBytes(12),
} = {}) {
  validateDirection(direction);
  const key = deriveKey(licenseKey, salt);
  const aad = additionalData(requestId, timestamp, direction);
  const cipher = createCipheriv('aes-256-gcm', key, nonce, { authTagLength: 16 });
  cipher.setAAD(aad);
  const plaintext = Buffer.from(JSON.stringify(payload), 'utf8');
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    v: 1,
    requestId,
    timestamp,
    salt: Buffer.from(salt).toString('base64url'),
    nonce: Buffer.from(nonce).toString('base64url'),
    ciphertext: ciphertext.toString('base64url'),
    tag: cipher.getAuthTag().toString('base64url'),
  };
}

export function decryptEnvelope(envelope, licenseKey, {
  direction = 'request',
  replayGuard = null,
} = {}) {
  validateDirection(direction);
  validateEnvelope(envelope);
  if (replayGuard) replayGuard.consume(envelope.requestId, envelope.timestamp);
  const salt = decodeExact(envelope.salt, 16, 'salt');
  const nonce = decodeExact(envelope.nonce, 12, 'nonce');
  const tag = decodeExact(envelope.tag, 16, 'tag');
  const ciphertext = decodeBounded(envelope.ciphertext, 1, 262_144, 'ciphertext');
  const key = deriveKey(licenseKey, salt);
  const decipher = createDecipheriv('aes-256-gcm', key, nonce, { authTagLength: 16 });
  decipher.setAAD(additionalData(envelope.requestId, envelope.timestamp, direction));
  decipher.setAuthTag(tag);
  let plaintext;
  try {
    plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch {
    throw new SecureChannelError('DECRYPTION_FAILED', 'Encrypted payload authentication failed', 401);
  }
  let payload;
  try {
    payload = JSON.parse(plaintext.toString('utf8'));
  } catch {
    throw new SecureChannelError('INVALID_SECURE_PAYLOAD', 'Decrypted payload is invalid', 400);
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new SecureChannelError('INVALID_SECURE_PAYLOAD', 'Decrypted payload must be an object');
  }
  return payload;
}

function deriveKey(licenseKey, salt) {
  if (typeof licenseKey !== 'string' || licenseKey.length < 48) {
    throw new SecureChannelError('INVALID_KEY_MATERIAL', 'Invalid encryption key material', 401);
  }
  return Buffer.from(hkdfSync(
    'sha256',
    Buffer.from(licenseKey, 'utf8'),
    salt,
    Buffer.from('wesi-aero-control-v1', 'utf8'),
    32,
  ));
}

function additionalData(requestId, timestamp, direction) {
  return Buffer.from(`1|${requestId}|${timestamp}|${direction}`, 'utf8');
}

function validateEnvelope(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || value.v !== 1) {
    throw new SecureChannelError('INVALID_ENVELOPE', 'Invalid encrypted envelope');
  }
  if (typeof value.requestId !== 'string' ||
      !/^[0-9a-f-]{36}$/i.test(value.requestId)) {
    throw new SecureChannelError('INVALID_ENVELOPE', 'Invalid request id');
  }
  for (const field of ['salt', 'nonce', 'ciphertext', 'tag']) {
    if (typeof value[field] !== 'string') {
      throw new SecureChannelError('INVALID_ENVELOPE', `Missing ${field}`);
    }
  }
}

function validateDirection(direction) {
  if (!['request', 'response'].includes(direction)) {
    throw new SecureChannelError('INVALID_DIRECTION', 'Invalid secure channel direction');
  }
}

function decodeExact(value, length, field) {
  return decodeBounded(value, length, length, field);
}

function decodeBounded(value, min, max, field) {
  let decoded;
  try {
    decoded = Buffer.from(value, 'base64url');
  } catch {
    throw new SecureChannelError('INVALID_ENVELOPE', `Invalid ${field}`);
  }
  if (decoded.length < min || decoded.length > max) {
    throw new SecureChannelError('INVALID_ENVELOPE', `Invalid ${field} length`);
  }
  return decoded;
}
