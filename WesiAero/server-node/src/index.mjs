import { createApiServer } from './api.mjs';
import { CommerceRepository } from './commerce.mjs';
import { loadConfig } from './config.mjs';
import { openDatabase } from './database.mjs';
import { StaticProfileProvisioner } from './provisioner.mjs';
import { GatewayRepository } from './repository.mjs';
import { PaymentOrchestrator } from './payments.mjs';
import { RouteServerClient } from './route-server-client.mjs';
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
const routeServer = new RouteServerClient({
  baseUrl: config.routeServerUrl,
  token: config.routeServerToken,
  timeoutMs: config.routeServerTimeoutMs,
});

if (process.env.WESI_AERO_SEED_DEMO === 'true') {
  const relayHost = process.env.WESI_AERO_RELAY_PUBLIC_HOST ||
    'wesi-aero-178-236-247-194.nip.io';
  commerce.upsertServer({
    id: 'wesi-relay',
    displayName: 'Wesi Relay',
    city: 'Wesi Relay',
    country: 'Foreign VPS',
    countryCode: 'XX',
    endpoint: `${relayHost}:8443`,
    protocols: ['vless-reality', 'vmess', 'wireguard'],
    load: 0.05,
    online: true,
    recommended: true,
    capacity: 500,
    tags: ['relay', 'xray', 'sing-box-ready', 'wireguard', 'prototype'],
    notes: 'VLESS/REALITY, VMess and standard WireGuard are live. Additional transports are staged separately.',
    transportConfig: {
      defaultProtocol: 'vless-reality',
      fallbackProtocol: 'vmess',
      realityPort: 8443,
      vmessPort: 8444,
      wireGuardPort: 51820,
      engines: ['sing-box', 'xray', 'native'],
    },
  });
}

const server = createApiServer({
  repository,
  commerce,
  payments,
  provisioner,
  routeServer,
  config,
});
server.listen(config.port, config.host, () => {
  process.stdout.write(
    `Wesi Aero control plane listening on http://${config.host}:${config.port}\n`,
  );
  if (!config.adminToken) {
    process.stdout.write('Administrative API is disabled\n');
  }
  if (routeServer.enabled) {
    process.stdout.write(`Route Server enabled: ${config.routeServerUrl}\n`);
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
