import { createApiServer } from './api.mjs';
import { loadConfig } from './config.mjs';
import { openDatabase } from './database.mjs';
import { StaticProfileProvisioner } from './provisioner.mjs';
import { GatewayRepository } from './repository.mjs';

const config = loadConfig();
if (config.adminToken && config.adminToken.length < 32) {
  throw new Error('WESI_AERO_ADMIN_TOKEN must contain at least 32 characters');
}

const database = openDatabase(config.databasePath);
const repository = new GatewayRepository(database, {
  leaseTtlSeconds: config.leaseTtlSeconds,
});
const provisioner = new StaticProfileProvisioner(config.profileDirectory);

if (process.env.WESI_AERO_SEED_DEMO === 'true') {
  repository.upsertNode({
    id: 'wesi-foreign-relay-candidate',
    city: 'Wesi Relay',
    country: 'Foreign VPS',
    countryCode: '',
    endpoint: 'wesi-ai-178-236-247-194.nip.io:8443',
    protocols: ['vless-reality', 'amneziawg'],
    load: 0.2,
    online: true,
    recommended: true,
  });
}

const server = createApiServer({ repository, provisioner, config });
server.listen(config.port, config.host, () => {
  process.stdout.write(
    `Wesi Aero control plane listening on http://${config.host}:${config.port}\n`,
  );
  if (!config.adminToken) {
    process.stdout.write('Administrative API is disabled\n');
  }
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => {
      database.close();
      process.exit(0);
    });
  });
}
