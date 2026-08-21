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

function hashSecret(secret, salt) {
  return scryptSync(secret, salt, SCRYPT_KEY_LENGTH, {
    N: 1 << 15,
    r: 8,
    p: 1,
    maxmem: 64 * 1024 * 1024,
  });
}
