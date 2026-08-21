import { createApiServer } from './api.mjs';
import { CommerceRepository } from './commerce.mjs';
import { loadConfig } from './config.mjs';
import { openDatabase } from './database.mjs';
import { StaticProfileProvisioner } from './provisioner.mjs';
import { GatewayRepository } from './repository.mjs';
import { PaymentOrchestrator } from './payments.mjs';
import { SecretVault } from './secret-vault.mjs';

const config = loadConfig();
if (config.adminToken && config.adminToken.length < 32) {
  throw new Error('WESI_AERO_ADMIN_TOKEN must contain at least 32 characters');
}

const database = openDatabase(config.databasePath);
const repository = new GatewayRepository(database, {
  leaseTtlSeconds: config.leaseTtlSeconds,
});
const secretVault = new SecretVault(config.masterKey);
const commerce = new CommerceRepository(database, repository, { secretVault });
commerce.seedDefaults();
const payments = new PaymentOrchestrator(commerce, config);
const provisioner = new StaticProfileProvisioner(config.profileDirectory);

if (process.env.WESI_AERO_SEED_DEMO === 'true') {
  commerce.upsertServer({
    id: 'wesi-foreign-relay-candidate',
    displayName: 'Wesi Relay',
    city: 'Wesi Relay',
    country: 'Foreign VPS',
    countryCode: '',
    endpoint: 'wesi-ai-178-236-247-194.nip.io:8443',
    protocols: ['vless-reality', 'amneziawg'],
    load: 0.2,
    online: true,
    recommended: true,
    capacity: 500,
    tags: ['relay', 'candidate'],
    notes: 'Public relay target; tunnel profile must be provisioned separately.',
    transportConfig: {
      realityPort: 8443,
      amneziaWgPort: 51820,
    },
  });
}

const server = createApiServer({
  repository,
  commerce,
  payments,
  provisioner,
  config,
});
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
