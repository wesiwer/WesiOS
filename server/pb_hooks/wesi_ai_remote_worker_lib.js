const PROTOCOL_VERSION = 1;
const REQUEST_PROTOCOL = "wesi-worker-hmac-v1";
const MAX_CLOCK_SKEW_MS = 90 * 1000;
const NONCE_TTL_MS = 3 * 60 * 1000;
const MAX_RECENT_NONCES = 32;
const MAX_PAYLOAD_JSON_BYTES = 512 * 1024;
const MESSAGE_KINDS = ["assignment", "progress", "checkpoint", "result", "cancel", "pause", "resume", "ack"];
const DESKTOP_PLATFORMS = ["windows", "linux", "macos"];

function text(value) {
  return String(value == null ? "" : value).trim();
}

function constantTimeEquals(a, b) {
  const left = String(a || "");
  const right = String(b || "");
  let diff = left.length ^ right.length;
  const max = Math.max(left.length, right.length);
  for (let i = 0; i < max; i++) {
    diff |= (i < left.length ? left.charCodeAt(i) : 0) ^
      (i < right.length ? right.charCodeAt(i) : 0);
  }
  return diff === 0;
}

function deriveRequestKey(secret, security) {
  const raw = text(secret);
  if (raw.length < 32 || raw.length > 256) {
    throw new Error("WRW_BAD_SECRET");
  }
  return String(security.sha256(raw));
}

function canonicalRequest(input) {
  const credentialId = text(input.credentialId);
  const workerId = text(input.workerId);
  const timestampMs = Number(input.timestampMs);
  const nonce = text(input.nonce);
  const method = text(input.method).toUpperCase();
  const path = text(input.path);
  const bodySha256 = text(input.bodySha256).toLowerCase();
  return [
    REQUEST_PROTOCOL,
    credentialId,
    workerId,
    String(timestampMs),
    nonce,
    method,
    path,
    bodySha256,
  ].join("\n");
}

function validateTarget(method, path) {
  const verb = text(method).toUpperCase();
  const target = text(path);
  if (!/^[A-Z]{3,8}$/.test(verb) ||
      !target.startsWith("/api/wesi/ai/workers/") ||
      target.length > 240 || target.indexOf("\\") >= 0 || target.indexOf("..") >= 0) {
    throw new Error("WRW_BAD_REQUEST_TARGET");
  }
}

function verifySignedRequest(input, security) {
  validateTarget(input.method, input.path);
  const credentialId = text(input.credentialId);
  const workerId = text(input.workerId);
  const nonce = text(input.nonce);
  const bodySha256 = text(input.bodySha256).toLowerCase();
  const signature = text(input.signature).toLowerCase();
  const timestampMs = Number(input.timestampMs);
  const payloadJson = String(input.payloadJson == null ? "" : input.payloadJson);
  const nowMs = Number(input.nowMs);
  const requestKey = text(input.requestKey);

  if (!/^[A-Za-z0-9_-]{20,96}$/.test(credentialId) ||
      !/^[A-Za-z0-9_-]{20,96}$/.test(workerId) ||
      !/^[A-Za-z0-9_-]{20,96}$/.test(nonce) ||
      !/^[a-f0-9]{64}$/.test(bodySha256) ||
      !/^[a-f0-9]{64}$/.test(signature) ||
      !Number.isFinite(timestampMs) ||
      Math.floor(timestampMs) !== timestampMs ||
      !Number.isFinite(nowMs) ||
      Math.abs(nowMs - timestampMs) > MAX_CLOCK_SKEW_MS ||
      requestKey.length !== 64) {
    return {ok: false, code: "WRW_UNAUTHORIZED"};
  }
  if (payloadJson.length > MAX_PAYLOAD_JSON_BYTES) {
    return {ok: false, code: "WRW_PAYLOAD_TOO_LARGE"};
  }
  const actualBody = String(security.sha256(payloadJson)).toLowerCase();
  if (!constantTimeEquals(actualBody, bodySha256)) {
    return {ok: false, code: "WRW_BODY_TAMPERED"};
  }
  const canonical = canonicalRequest({
    credentialId: credentialId,
    workerId: workerId,
    timestampMs: timestampMs,
    nonce: nonce,
    method: input.method,
    path: input.path,
    bodySha256: bodySha256,
  });
  const expected = String(security.hs256(canonical, requestKey)).toLowerCase();
  if (!constantTimeEquals(expected, signature)) {
    return {ok: false, code: "WRW_UNAUTHORIZED"};
  }
  return {ok: true};
}

function acceptNonce(recent, nonce, nowMs) {
  const source = Array.isArray(recent) ? recent : [];
  const kept = [];
  for (const item of source) {
    if (!item || typeof item !== "object") continue;
    const value = text(item.nonce);
    const at = Number(item.at);
    if (!/^[A-Za-z0-9_-]{20,96}$/.test(value) || !Number.isFinite(at)) continue;
    if (nowMs - at <= NONCE_TTL_MS && nowMs >= at - MAX_CLOCK_SKEW_MS) {
      if (value === nonce) return {ok: false, values: kept};
      kept.push({nonce: value, at: at});
    }
  }
  kept.push({nonce: nonce, at: nowMs});
  if (kept.length > MAX_RECENT_NONCES) {
    kept.splice(0, kept.length - MAX_RECENT_NONCES);
  }
  return {ok: true, values: kept};
}

function parsePayloadJson(raw) {
  const payloadJson = String(raw == null ? "" : raw);
  if (!payloadJson || payloadJson.length > MAX_PAYLOAD_JSON_BYTES) {
    throw new Error("WRW_BAD_PAYLOAD");
  }
  let parsed;
  try {
    parsed = JSON.parse(payloadJson);
  } catch (_) {
    throw new Error("WRW_BAD_PAYLOAD");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("WRW_BAD_PAYLOAD");
  }
  return parsed;
}

function validateTicket(ticket, nowMs) {
  const value = ticket && typeof ticket === "object" && !Array.isArray(ticket) ? ticket : {};
  const ticketId = text(value.ticketId || value.ticket);
  const workerId = text(value.workerId || value.worker);
  const workerName = text(value.workerName || value.name);
  const fingerprint = text(value.deviceFingerprint || value.fp).toLowerCase();
  const nonce = text(value.nonce);
  const expiresAtMs = value.expiresAtMs != null
    ? Number(value.expiresAtMs)
    : Date.parse(String(value.expiresAt || value.exp || ""));
  const lanHint = value.lanHint == null ? null : text(value.lanHint);
  if (!/^[A-Za-z0-9_-]{20,96}$/.test(ticketId) ||
      !/^[A-Za-z0-9_-]{20,96}$/.test(workerId) ||
      !/^[A-Fa-f0-9]{32,128}$/.test(fingerprint) ||
      !/^[A-Za-z0-9_-]{20,96}$/.test(nonce) ||
      !workerName || workerName.length > 120 ||
      !Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs ||
      expiresAtMs - nowMs > 15 * 60 * 1000 ||
      (lanHint != null && lanHint.length > 160)) {
    throw new Error("WRW_BAD_PAIRING_TICKET");
  }
  return {
    ticketId: ticketId,
    workerId: workerId,
    workerName: workerName,
    deviceFingerprint: fingerprint,
    nonce: nonce,
    expiresAtMs: Math.floor(expiresAtMs),
    lanHint: lanHint,
  };
}

function validateHeartbeat(payload, authenticatedWorkerId, nowMs) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
      Number(payload.v) !== PROTOCOL_VERSION || !payload.worker || typeof payload.worker !== "object") {
    throw new Error("WRW_BAD_HEARTBEAT");
  }
  const worker = payload.worker;
  const id = text(worker.id);
  const name = text(worker.name);
  const platform = text(worker.platform);
  const status = text(worker.status);
  const sentAtMs = Date.parse(String(payload.sentAt || ""));
  const intField = function(key) {
    const value = Number(worker[key]);
    if (!Number.isFinite(value) || Math.floor(value) !== value || value < 0) throw new Error("WRW_BAD_HEARTBEAT");
    return value;
  };
  const numberField = function(key) {
    const value = Number(worker[key]);
    if (!Number.isFinite(value) || value < 0) throw new Error("WRW_BAD_HEARTBEAT");
    return value;
  };
  if (id !== authenticatedWorkerId ||
      !/^[A-Za-z0-9_-]{20,96}$/.test(id) ||
      !name || name.length > 120 ||
      DESKTOP_PLATFORMS.indexOf(platform) < 0 ||
      ["offline", "online", "busy", "paused"].indexOf(status) < 0 ||
      !Number.isFinite(sentAtMs) || Math.abs(nowMs - sentAtMs) > 2 * 60 * 1000) {
    throw new Error("WRW_BAD_HEARTBEAT");
  }
  const cpuCores = intField("cpuCores");
  const cpuLoadPercent = numberField("cpuLoadPercent");
  const totalRamMb = intField("totalRamMb");
  const availableRamMb = intField("availableRamMb");
  const totalGpuVramMb = intField("totalGpuVramMb");
  const freeGpuVramMb = intField("freeGpuVramMb");
  const freeDiskMb = intField("freeDiskMb");
  if (cpuCores < 1 || cpuLoadPercent > 100 || availableRamMb > totalRamMb || freeGpuVramMb > totalGpuVramMb) {
    throw new Error("WRW_BAD_HEARTBEAT");
  }
  const capabilities = Array.isArray(worker.capabilities) ? worker.capabilities.map(text) : null;
  const packs = Array.isArray(worker.installedPacks) ? worker.installedPacks.map(text) : null;
  if (!capabilities || capabilities.length > 64 || !packs || packs.length > 16) {
    throw new Error("WRW_BAD_HEARTBEAT");
  }
  for (const key of ["activeLightJobs", "activeCpuJobs", "activeHeavyJobs", "activeGpuJobs"]) intField(key);
  return payload;
}

function validateMessage(raw) {
  const message = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const idPattern = /^[A-Za-z0-9._:-]{1,128}$/;
  const messageId = text(message.messageId);
  const jobId = text(message.jobId);
  const kind = text(message.kind);
  const sequence = Number(message.sequence);
  const createdAtMs = Date.parse(String(message.createdAt || ""));
  const payload = message.payload && typeof message.payload === "object" && !Array.isArray(message.payload)
    ? message.payload : {};
  if (Number(message.v) !== PROTOCOL_VERSION ||
      !idPattern.test(messageId) || !idPattern.test(jobId) ||
      MESSAGE_KINDS.indexOf(kind) < 0 ||
      !Number.isFinite(sequence) || Math.floor(sequence) !== sequence || sequence < 0 ||
      !Number.isFinite(createdAtMs) || Object.keys(payload).length > 64) {
    throw new Error("WRW_BAD_JOB_MESSAGE");
  }
  let encoded;
  try { encoded = JSON.stringify(message); } catch (_) { throw new Error("WRW_BAD_JOB_MESSAGE"); }
  if (encoded.length > 128 * 1024) throw new Error("WRW_BAD_JOB_MESSAGE");
  return message;
}

function publicCredentialPayload(payload) {
  return {
    credentialId: text(payload.credentialId),
    workerId: text(payload.workerId),
    issuedAt: text(payload.issuedAt),
    expiresAt: text(payload.expiresAt),
    revokedAt: text(payload.revokedAt) || null,
  };
}

module.exports = {
  PROTOCOL_VERSION,
  REQUEST_PROTOCOL,
  MAX_CLOCK_SKEW_MS,
  NONCE_TTL_MS,
  MAX_RECENT_NONCES,
  MAX_PAYLOAD_JSON_BYTES,
  constantTimeEquals,
  deriveRequestKey,
  canonicalRequest,
  validateTarget,
  verifySignedRequest,
  acceptNonce,
  parsePayloadJson,
  validateTicket,
  validateHeartbeat,
  validateMessage,
  publicCredentialPayload,
};
