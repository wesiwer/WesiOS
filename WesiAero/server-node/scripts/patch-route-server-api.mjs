import fs from 'node:fs';

const file = 'WesiAero/server-node/src/api.mjs';
let source = fs.readFileSync(file, 'utf8');

function replaceOnce(before, after, label) {
  const count = source.split(before).length - 1;
  if (count !== 1) throw new Error(`${label}: expected one match, found ${count}`);
  source = source.replace(before, after);
}

replaceOnce(
`  provisioner,\n  config,\n}) {`,
`  provisioner,\n  routeServer = null,\n  config,\n}) {`,
'createApiServer routeServer parameter');

replaceOnce(
`        provisioner,\n        config,\n        replayGuard,`,
`        provisioner,\n        routeServer,\n        config,\n        replayGuard,`,
'route context routeServer');

replaceOnce(
`    provisioner,\n    config,\n    replayGuard,`,
`    provisioner,\n    routeServer,\n    config,\n    replayGuard,`,
'route destructuring routeServer');

replaceOnce(
`          commerce,\n          provisioner,\n        }),`,
`          commerce,\n          provisioner,\n          routeServer,\n        }),`,
'dispatch routeServer');

replaceOnce(
`    const lease = repository.reserveLease({\n      user: access.user,\n      deviceId: body.deviceId,\n      nodeId: body.nodeId,\n      protocol: body.protocol,\n    });`,
`    const resolved = await resolveLeaseRoute({\n      commerce,\n      routeServer,\n      deviceId: body.deviceId,\n      requestedNodeId: body.nodeId,\n      requestedProtocol: body.protocol,\n    });\n    const lease = repository.reserveLease({\n      user: access.user,\n      deviceId: body.deviceId,\n      nodeId: resolved.nodeId,\n      protocol: resolved.protocol,\n    });`,
'legacy lease route selection');

replaceOnce(
`  commerce,\n  provisioner,\n}) {`,
`  commerce,\n  provisioner,\n  routeServer,\n}) {`,
'dispatch signature routeServer');

replaceOnce(
`    const lease = repository.reserveLease({\n      user: access.user,\n      deviceId: payload.deviceId,\n      nodeId: payload.nodeId,\n      protocol: payload.protocol,\n    });`,
`    const resolved = await resolveLeaseRoute({\n      commerce,\n      routeServer,\n      deviceId: payload.deviceId,\n      requestedNodeId: payload.nodeId,\n      requestedProtocol: payload.protocol,\n    });\n    const lease = repository.reserveLease({\n      user: access.user,\n      deviceId: payload.deviceId,\n      nodeId: resolved.nodeId,\n      protocol: resolved.protocol,\n    });`,
'secure lease route selection');

const anchor = `function requireAccess(request, repository, commerce) {`;
const helper = `async function resolveLeaseRoute({\n  commerce,\n  routeServer,\n  deviceId,\n  requestedNodeId,\n  requestedProtocol,\n}) {\n  const server = commerce?.getServer?.(requestedNodeId);\n  const poolId = server?.transportConfig?.routePoolId;\n  if (!poolId) {\n    return { nodeId: requestedNodeId, protocol: requestedProtocol };\n  }\n  if (!routeServer?.enabled) {\n    throw new HttpError(503, 'ROUTE_SERVER_UNAVAILABLE', 'Automatic routing is unavailable');\n  }\n  try {\n    const selected = await routeServer.select({\n      clientId: deviceId,\n      poolId,\n      protocol: requestedProtocol,\n    });\n    return {\n      nodeId: selected.nodeId || requestedNodeId,\n      protocol: selected.protocol || requestedProtocol,\n    };\n  } catch (error) {\n    throw new HttpError(\n      Number(error?.statusCode) || 503,\n      error?.code || 'ROUTE_SERVER_UNAVAILABLE',\n      error?.message || 'Automatic routing is unavailable',\n    );\n  }\n}\n\n`;
if (!source.includes(anchor)) throw new Error('helper anchor missing');
source = source.replace(anchor, helper + anchor);

fs.writeFileSync(file, source);
console.log('route server API patch applied');
