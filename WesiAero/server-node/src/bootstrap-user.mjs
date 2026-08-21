import { loadConfig } from './config.mjs';
import { openDatabase } from './database.mjs';
import { GatewayRepository } from './repository.mjs';

const [displayName, maxSessionsRaw = '1', quotaGiBRaw = '0'] = process.argv.slice(2);
if (!displayName) {
  process.stderr.write(
    'Usage: npm run bootstrap-user -- "Display name" [maxSessions] [quotaGiB]\n',
  );
  process.exit(2);
}

const maxSessions = Number.parseInt(maxSessionsRaw, 10);
const quotaGiB = Number.parseInt(quotaGiBRaw, 10);
const quotaBytes = quotaGiB === 0 ? 0 : quotaGiB * 1024 ** 3;
const config = loadConfig();
const database = openDatabase(config.databasePath);
try {
  const repository = new GatewayRepository(database, {
    leaseTtlSeconds: config.leaseTtlSeconds,
  });
  const user = repository.createUser({ displayName, maxSessions, quotaBytes });
  process.stdout.write(`${JSON.stringify(user, null, 2)}\n`);
  process.stdout.write('Store the token now: it cannot be recovered from the database.\n');
} finally {
  database.close();
}

