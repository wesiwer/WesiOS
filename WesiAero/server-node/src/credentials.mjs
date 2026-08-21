import {
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';

const SCRYPT_KEY_LENGTH = 64;

export function createAccessCredential() {
  const userId = randomUUID();
  const secret = randomBytes(32).toString('base64url');
  const salt = randomBytes(16);
  const hash = hashSecret(secret, salt);
  return {
    userId,
    token: `wsg.${userId}.${secret}`,
    salt,
    hash,
  };
}

export function createLicenseCredential() {
  const licenseId = randomUUID();
  const compactId = licenseId.replaceAll('-', '');
  const secret = randomBytes(24).toString('base64url');
  const salt = randomBytes(16);
  return {
    licenseId,
    key: `WA1-${compactId}-${secret}`,
    prefix: `WA1-${compactId.slice(0, 8)}`,
    salt,
    hash: hashSecret(secret, salt),
    secret,
  };
}

export function parseLicenseKey(key) {
  if (typeof key !== 'string') return null;
  const match = /^WA1-([0-9a-f]{32})-([A-Za-z0-9_-]{24,64})$/i.exec(key.trim());
  if (!match) return null;
  const compact = match[1].toLowerCase();
  const licenseId = [
    compact.slice(0, 8),
    compact.slice(8, 12),
    compact.slice(12, 16),
    compact.slice(16, 20),
    compact.slice(20),
  ].join('-');
  return { licenseId, secret: match[2] };
}

export function parseAccessToken(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== 'wsg') return null;
  const [, userId, secret] = parts;
  if (!/^[0-9a-f-]{36}$/i.test(userId) || secret.length < 32) return null;
  return { userId, secret };
}

export function verifySecret(secret, salt, expectedHash) {
  if (!ArrayBuffer.isView(salt) || !ArrayBuffer.isView(expectedHash)) return false;
  const saltBuffer = Buffer.from(salt.buffer, salt.byteOffset, salt.byteLength);
  const expectedBuffer = Buffer.from(
    expectedHash.buffer,
    expectedHash.byteOffset,
    expectedHash.byteLength,
  );
  const actual = hashSecret(secret, saltBuffer);
  return actual.length === expectedBuffer.length &&
    timingSafeEqual(actual, expectedBuffer);
}

export function safeEqualText(actual, expected) {
  if (typeof actual !== 'string' || typeof expected !== 'string') return false;
  const left = Buffer.from(actual);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

export function hashSecret(secret, salt) {
  return scryptSync(secret, salt, SCRYPT_KEY_LENGTH, {
    N: 1 << 15,
    r: 8,
    p: 1,
    maxmem: 64 * 1024 * 1024,
  });
}
