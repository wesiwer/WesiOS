import path from 'node:path';

function intFromEnv(environment, name, fallback, {
  min = 1,
  max = Number.MAX_SAFE_INTEGER,
} = {}) {
  const raw = environment[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

export function loadConfig(environment = process.env) {
  const cwd = process.cwd();
  const publicBaseUrl = environment.WESI_AERO_PUBLIC_BASE_URL ||
    'http://127.0.0.1:8790';
  const paymentReturnUrl = environment.WESI_AERO_PAYMENT_RETURN_URL ||
    new URL('/v1/payment-return', publicBaseUrl).toString();

  const allowInsecureDevDefaults =
    environment.WESI_AERO_ALLOW_INSECURE_DEV_DEFAULTS === 'true';
  const masterKey = environment.WESI_AERO_MASTER_KEY ||
    (allowInsecureDevDefaults
      ? (environment.WESI_AERO_ADMIN_TOKEN || 'development-only-wesi-aero-master-key-change-me')
      : null);
  if (typeof masterKey !== 'string' || masterKey.length < 32) {
    throw new Error(
      'WESI_AERO_MASTER_KEY with at least 32 characters is required. ' +
      'Insecure development defaults require explicit ' +
      'WESI_AERO_ALLOW_INSECURE_DEV_DEFAULTS=true.',
    );
  }

  return Object.freeze({
    host: environment.WESI_AERO_HOST || '127.0.0.1',
    port: intFromEnv(environment, 'WESI_AERO_PORT', 8790, {
      min: 1,
      max: 65535,
    }),
    databasePath: path.resolve(
      cwd,
      environment.WESI_AERO_DATABASE || 'data/wesi-aero.db',
    ),
    profileDirectory: path.resolve(
      cwd,
      environment.WESI_AERO_PROFILE_DIR || 'profiles',
    ),
    adminToken: environment.WESI_AERO_ADMIN_TOKEN || null,
    leaseTtlSeconds: intFromEnv(environment, 'WESI_AERO_LEASE_TTL_SECONDS', 120, {
      min: 30,
      max: 900,
    }),
    bodyLimitBytes: intFromEnv(environment, 'WESI_AERO_BODY_LIMIT_BYTES', 65_536, {
      min: 1024,
      max: 1_048_576,
    }),
    # Privacy/security-sensitive features are opt-in. A missing environment
    # variable must never silently enable request metadata logging or mock money
    # flows in a production-like deployment.
    technicalLogs: environment.WESI_AERO_TECHNICAL_LOGS === 'true',
    publicBaseUrl,
    paymentReturnUrl,
    allowMockPayments: environment.WESI_AERO_ALLOW_MOCK_PAYMENTS === 'true',
    yookassaShopId: environment.WESI_AERO_YOOKASSA_SHOP_ID || null,
    yookassaSecretKey: environment.WESI_AERO_YOOKASSA_SECRET_KEY || null,
    cryptoPayToken: environment.WESI_AERO_CRYPTO_PAY_TOKEN || null,
    cryptoPayTestnet: environment.WESI_AERO_CRYPTO_PAY_TESTNET !== 'false',
    masterKey,
  });
}
