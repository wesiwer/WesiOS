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
  const network = {
    rxBytesPerSecond: Math.max(0, Math.round((currentNetwork.rx - previousNetwork.rx) / seconds)),
    txBytesPerSecond: Math.max(0, Math.round((currentNetwork.tx - previousNetwork.tx) / seconds)),
  };
  previousNetwork = currentNetwork;
  previousAt = now;

  const servicePairs = await Promise.all(services.map(async (name) => [name, await serviceState(name)]));
  return {
    nodeId,
    observedAt: new Date(now).toISOString(),
    uptimeSeconds: Math.round(os.uptime()),
    loadAverage: os.loadavg(),
    cpuLoadRatio: cpuLoadRatio(),
    memory: memory(),
    network,
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
