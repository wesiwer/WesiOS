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
    technicalLogs: environment.WESI_AERO_TECHNICAL_LOGS !== 'false',
  });
}
