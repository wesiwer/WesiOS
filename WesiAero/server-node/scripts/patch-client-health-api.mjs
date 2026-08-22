import fs from 'node:fs';

const file = 'WesiAero/server-node/src/api.mjs';
let source = fs.readFileSync(file, 'utf8');
const anchor = `  if (payload.action === 'lease.heartbeat') {\n`;
if (!source.includes(anchor)) throw new Error('lease heartbeat anchor missing');
if (source.includes("payload.action === 'route.health.report'")) {
  console.log('client health route already present');
  process.exit(0);
}
const block = `  if (payload.action === 'route.health.report') {\n    commerce.assertDeviceBound(access.license.id, payload.deviceId);\n    const server = commerce.getServer(payload.nodeId);\n    const poolId = server?.transportConfig?.routePoolId;\n    if (!poolId || !routeServer?.enabled) {\n      return { accepted: false, reason: 'ROUTE_SERVER_NOT_USED' };\n    }\n    const result = await routeServer.reportClientHealth({\n      clientId: payload.deviceId,\n      poolId,\n      nodeId: payload.nodeId,\n      protocol: payload.protocol,\n      result: payload.result ?? {},\n    });\n    return { accepted: result.accepted === true, classification: result.classification ?? null };\n  }\n`;
source = source.replace(anchor, block + anchor);
fs.writeFileSync(file, source);
console.log('client health route applied');
