import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';

export class SecretVault {
  constructor(masterKey) {
    if (typeof masterKey !== 'string' || masterKey.length < 32) {
      throw new Error('WESI_AERO_MASTER_KEY must contain at least 32 characters');
    }
    this.key = createHash('sha256').update(masterKey, 'utf8').digest();
  }

  seal(value, context) {
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, nonce);
    cipher.setAAD(Buffer.from(context, 'utf8'));
    const ciphertext = Buffer.concat([
      cipher.update(String(value), 'utf8'),
      cipher.final(),
    ]);
    return [
      'v1',
      nonce.toString('base64url'),
      ciphertext.toString('base64url'),
      cipher.getAuthTag().toString('base64url'),
    ].join('.');
  }

  open(envelope, context) {
    const parts = typeof envelope === 'string' ? envelope.split('.') : [];
    if (parts.length !== 4 || parts[0] !== 'v1') {
      throw new Error('Invalid encrypted secret');
    }
    const nonce = Buffer.from(parts[1], 'base64url');
    const ciphertext = Buffer.from(parts[2], 'base64url');
    const tag = Buffer.from(parts[3], 'base64url');
    const decipher = createDecipheriv('aes-256-gcm', this.key, nonce);
    decipher.setAAD(Buffer.from(context, 'utf8'));
    decipher.setAuthTag(tag);
    return Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]).toString('utf8');
  }
}
