import os from 'node:os';
import fs from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const routeServerUrl = (process.env.WESI_AERO_ROUTE_SERVER_URL || 'http://127.0.0.1:8793').replace(/\/$/, '');
const token = process.env.WESI_AERO_ROUTE_SERVER_TOKEN || '';
const nodeId = process.env.WESI_AERO_NODE_ID || 'ireland-bs';
const intervalMs = Number(process.env.WESI_AERO_NODE_AGENT_INTERVAL_MS || 10000);
const services = (process.env.WESI_AERO_NODE_SERVICES || 'wesi-aero-ireland-bs').split(',').map((v) => v.trim()).filter(Boolean);
const xrayBinary = process.env.WESI_AERO_XRAY_BINARY || '/opt/wesi-aero-xray/xray';
const tunnelPort = Number(process.env.WESI_AERO_TUNNEL_PORT || 8443);

let previousNetwork = readNetworkTotals();
let previousAt = Date.now();

async function serviceState(name) {
  try {
    const { stdout } = await execFileAsync('systemctl', ['is-active', name], { timeout: 1500 });
    return stdout.trim() === 'active';
  } catch {
    return false;
  }
}

async function xrayVersion() {
  try {
    const { stdout } = await execFileAsync(xrayBinary, ['version'], { timeout: 2000 });
    const first = stdout.split('\n').map((value) => value.trim()).find(Boolean) || '';
    return first.replace(/^Xray\s+/i, '').trim() || null;
  } catch {
    return null;
  }
}

async function activeTcpSessions(port) {
  try {
    const { stdout } = await execFileAsync('ss', ['-Htn', 'state', 'established'], { timeout: 2000 });
    const marker = `:${port}`;
    return stdout.split('\n').filter((line) => line.includes(marker)).length;
  } catch {
    return 0;
  }
}

function readNetworkTotals() {
  try {
    const lines = fs.readFileSync('/proc/net/dev', 'utf8').split('\n').slice(2);
    let rx = 0;
    let tx = 0;
    for (const line of lines) {
      const [namePart, dataPart] = line.split(':');
      if (!dataPart) continue;
      const name = namePart.trim();
      if (name === 'lo') continue;
      const fields = dataPart.trim().split(/\s+/).map(Number);
      rx += fields[0] || 0;
      tx += fields[8] || 0;
    }
    return { rx, tx };
  } catch {
    return { rx: 0, tx: 0 };
  }
}

function networkCapacityBitsPerSecond() {
  let total = 0;
  try {
    for (const name of fs.readdirSync('/sys/class/net')) {
      if (name === 'lo') continue;
      try {
        const operstate = fs.readFileSync(`/sys/class/net/${name}/operstate`, 'utf8').trim();
        if (operstate !== 'up') continue;
        const speedMbps = Number(fs.readFileSync(`/sys/class/net/${name}/speed`, 'utf8').trim());
        if (Number.isFinite(speedMbps) && speedMbps > 0) total += speedMbps * 1_000_000;
      } catch {
        // Virtual/cloud interfaces may not expose link speed.
      }
    }
  } catch {
    return null;
  }
  return total > 0 ? total : null;
}

function memory() {
  const total = os.totalmem();
  const free = os.freemem();
  return {
    totalBytes: total,
    usedBytes: Math.max(0, total - free),
    usedRatio: total > 0 ? Math.max(0, Math.min(1, (total - free) / total)) : 0,
  };
}

function cpuLoadRatio() {
  const cpus = Math.max(1, os.cpus().length);
  return Math.max(0, Math.min(1, os.loadavg()[0] / cpus));
}

async function collect() {
  const now = Date.now();
  const currentNetwork = readNetworkTotals();
  const seconds = Math.max(0.001, (now - previousAt) / 1000);
  const rxBytesPerSecond = Math.max(0, Math.round((currentNetwork.rx - previousNetwork.rx) / seconds));
  const txBytesPerSecond = Math.max(0, Math.round((currentNetwork.tx - previousNetwork.tx) / seconds));
  previousNetwork = currentNetwork;
  previousAt = now;

  const capacityBps = networkCapacityBitsPerSecond();
  const currentBitsPerSecond = (rxBytesPerSecond + txBytesPerSecond) * 8;
  const networkUtilizationRatio = capacityBps && capacityBps > 0
      ? Math.max(0, Math.min(1, currentBitsPerSecond / capacityBps))
      : null;

  const [servicePairs, version, activeSessions] = await Promise.all([
    Promise.all(services.map(async (name) => [name, await serviceState(name)])),
    xrayVersion(),
    activeTcpSessions(tunnelPort),
  ]);

  return {
    nodeId,
    observedAt: new Date(now).toISOString(),
    uptimeSeconds: Math.round(os.uptime()),
    loadAverage: os.loadavg(),
    cpuLoadRatio: cpuLoadRatio(),
    memory: memory(),
    network: {
      rxBytesPerSecond,
      txBytesPerSecond,
      capacityBitsPerSecond: capacityBps,
      utilizationRatio: networkUtilizationRatio,
    },
    activeSessions,
    versions: {
      xray: version,
    },
    services: Object.fromEntries(servicePairs),
  };
}

async function publish() {
  const telemetry = await collect();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(`${routeServerUrl}/v1/node-telemetry`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(telemetry),
    });
    if (!response.ok) throw new Error(`HTTP_${response.status}`);
  } finally {
    clearTimeout(timeout);
  }
}

async function loop() {
  try { await publish(); } catch (error) { console.error('[node-agent] publish failed', error?.message || error); }
  const jitter = Math.round(intervalMs * (0.85 + Math.random() * 0.3));
  setTimeout(loop, jitter).unref();
}

console.log(`[node-agent] node=${nodeId} routeServer=${routeServerUrl}`);
await loop();
