const dataAccess = require(`${__hooks}/wesi_ai_data_access.js`);
const rw = require(`${__hooks}/wesi_ai_remote_worker_lib.js`);
const atomic = require(`${__hooks}/wesi_sync_atomic.js`);

const COLL_PAIRING = "ai_remote_worker_pairings";
const COLL_CREDENTIAL = "ai_remote_worker_credentials";
const COLL_HEARTBEAT = "ai_remote_worker_heartbeats";
const COLL_MESSAGE = "ai_remote_worker_messages";
const OWNER_ORG = "wesi-inc";
const PAIR_TTL_MS = 5 * 60 * 1000;
const CREDENTIAL_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const MAX_MESSAGES_PER_WORKER = 256;
const MAX_PENDING_TO_WORKER = 128;

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function randomId(length) {
  return $security.randomStringWithAlphabet(
    length,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
  );
}

function findRecord(app, ownerId, coll, rid) {
  return dataAccess.first(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
    {owner: ownerId, coll: coll, rid: rid},
  );
}

function findRecordAnyOwner(app, coll, rid) {
  return dataAccess.first(
    app,
    "wesios_records",
    "coll={:coll} && rid={:rid} && deleted=false",
    {coll: coll, rid: rid},
  );
}

function rowsForWorker(app, ownerId, coll, workerId, limit) {
  return dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && org={:worker} && deleted=false",
    "stamp",
    Math.max(1, Math.min(Number(limit || MAX_MESSAGES_PER_WORKER), MAX_MESSAGES_PER_WORKER)),
    0,
    {owner: ownerId, coll: coll, worker: workerId},
  );
}

function upsert(app, ownerId, org, coll, rid, payload) {
  const now = new Date().toISOString();
  atomic.commit(app, {
    owner: ownerId,
    org: org || OWNER_ORG,
    coll: coll,
    rid: rid,
    payload: payload,
    stamp: now,
    deleted: false,
  });
  return findRecord(app, ownerId, coll, rid);
}

function aiContext(e) {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  return ctx;
}

function ticketPayload(record) {
  const payload = payloadOf(record);
  return {
    ticketId: String(payload.ticketId || record.getString("rid") || ""),
    workerId: String(payload.workerId || record.getString("org") || ""),
    workerName: String(payload.workerName || ""),
    deviceFingerprint: String(payload.deviceFingerprint || ""),
    nonce: String(payload.nonce || ""),
    expiresAtMs: Number(payload.expiresAtMs || 0),
    lanHint: payload.lanHint == null ? null : String(payload.lanHint),
  };
}

function activeCredentialForWorker(app, ownerId, workerId, nowMs) {
  const rows = rowsForWorker(app, ownerId, COLL_CREDENTIAL, workerId, 32);
  for (let i = rows.length - 1; i >= 0; i--) {
    const payload = payloadOf(rows[i]);
    const expiresAtMs = Date.parse(String(payload.expiresAt || ""));
    if (!String(payload.revokedAt || "") && Number.isFinite(expiresAtMs) && expiresAtMs > nowMs) {
      return rows[i];
    }
  }
  return null;
}

function ownsWorker(app, ownerId, workerId) {
  return rowsForWorker(app, ownerId, COLL_CREDENTIAL, workerId, 32).length > 0;
}

function workerAuth(e, path) {
  const body = e.requestInfo().body || {};
  const payloadJson = typeof body.payloadJson === "string" ? body.payloadJson : "";
  const credentialId = String(e.request.header.get("X-Wesi-Worker-Credential") || "").trim();
  const workerId = String(e.request.header.get("X-Wesi-Worker-Id") || "").trim();
  const timestampMs = Number(e.request.header.get("X-Wesi-Worker-Timestamp") || 0);
  const nonce = String(e.request.header.get("X-Wesi-Worker-Nonce") || "").trim();
  const bodySha256 = String(e.request.header.get("X-Wesi-Worker-Body-Sha256") || "").trim().toLowerCase();
  const signature = String(e.request.header.get("X-Wesi-Worker-Signature") || "").trim().toLowerCase();
  const credential = findRecordAnyOwner(e.app, COLL_CREDENTIAL, credentialId);
  if (!credential) return {ok: false, code: "WRW_UNAUTHORIZED"};
  const credentialPayload = payloadOf(credential);
  const ownerId = credential.getString("owner");
  const expiresAtMs = Date.parse(String(credentialPayload.expiresAt || ""));
  const nowMs = Date.now();
  if (String(credentialPayload.workerId || credential.getString("org") || "") !== workerId ||
      String(credentialPayload.revokedAt || "") ||
      !Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs) {
    return {ok: false, code: "WRW_UNAUTHORIZED"};
  }
  const verified = rw.verifySignedRequest({
    credentialId: credentialId,
    workerId: workerId,
    timestampMs: timestampMs,
    nonce: nonce,
    method: e.request.method,
    path: path,
    bodySha256: bodySha256,
    signature: signature,
    payloadJson: payloadJson,
    requestKey: String(credentialPayload.requestKey || ""),
    nowMs: nowMs,
  }, $security);
  if (!verified.ok) return verified;
  const nonceState = rw.acceptNonce(credentialPayload.recentNonces, nonce, nowMs);
  if (!nonceState.ok) return {ok: false, code: "WRW_REPLAYED_REQUEST"};
  credentialPayload.recentNonces = nonceState.values;
  credentialPayload.lastAuthenticatedAt = new Date(nowMs).toISOString();
  atomic.commit(e.app, {
    owner: credential.getString("owner"),
    org: credential.getString("org"),
    coll: credential.getString("coll"),
    rid: credential.getString("rid"),
    payload: credentialPayload,
    stamp: new Date(nowMs).toISOString(),
    deleted: false,
  });
  let payload;
  try { payload = rw.parsePayloadJson(payloadJson); }
  catch (error) { return {ok: false, code: String(error.message || "WRW_BAD_PAYLOAD")}; }
  return {
    ok: true,
    ownerId: ownerId,
    workerId: workerId,
    credential: credential,
    credentialPayload: credentialPayload,
    payload: payload,
  };
}

function messageRid(direction, workerId, messageId) {
  return "wrw-msg:" + $security.sha256(direction + "|" + workerId + "|" + messageId);
}

function messageRows(app, ownerId, workerId) {
  return rowsForWorker(app, ownerId, COLL_MESSAGE, workerId, MAX_MESSAGES_PER_WORKER);
}

function messageOrder(a, b) {
  const job = String(a.jobId || "").localeCompare(String(b.jobId || ""));
  if (job !== 0) return job;
  const aGeneration = Number((a.payload && a.payload.generation) || 0);
  const bGeneration = Number((b.payload && b.payload.generation) || 0);
  if (aGeneration !== bGeneration) return aGeneration - bGeneration;
  const aSequence = Number(a.sequence || 0);
  const bSequence = Number(b.sequence || 0);
  if (aSequence !== bSequence) return aSequence - bSequence;
  return String(a.messageId || "").localeCompare(String(b.messageId || ""));
}

function saveMessage(app, ownerId, workerId, direction, message) {
  const rid = messageRid(direction, workerId, String(message.messageId || ""));
  const existing = findRecord(app, ownerId, COLL_MESSAGE, rid);
  if (existing) {
    const existingPayload = payloadOf(existing);
    if (existingPayload.direction !== direction ||
        JSON.stringify(existingPayload.message || {}) !== JSON.stringify(message)) {
      throw new BadRequestError("Wesi Worker message id conflict");
    }
    return existing;
  }
  const rows = messageRows(app, ownerId, workerId);
  const pendingOutbound = rows.filter(function(row) {
    const p = payloadOf(row);
    return p.direction === "to_worker" && p.acked !== true;
  }).length;
  if (direction === "to_worker" && pendingOutbound >= MAX_PENDING_TO_WORKER) {
    throw new BadRequestError("Очередь Wesi Worker переполнена");
  }
  if (rows.length >= MAX_MESSAGES_PER_WORKER) {
    const removable = rows.filter(function(row) {
      const p = payloadOf(row);
      return p.acked === true;
    });
    for (let i = 0; i < removable.length && rows.length - i >= MAX_MESSAGES_PER_WORKER; i++) {
      const row = removable[i];
      atomic.commit(app, {
        owner: row.getString("owner"),
        org: row.getString("org"),
        coll: row.getString("coll"),
        rid: row.getString("rid"),
        payload: payloadOf(row),
        stamp: new Date().toISOString(),
        deleted: true,
      });
    }
    if (messageRows(app, ownerId, workerId).length >= MAX_MESSAGES_PER_WORKER) {
      throw new BadRequestError("Хранилище сообщений Wesi Worker заполнено");
    }
  }
  return upsert(app, ownerId, workerId, COLL_MESSAGE, rid, {
    direction: direction,
    acked: false,
    workerId: workerId,
    messageId: String(message.messageId || ""),
    message: message,
    createdAt: new Date().toISOString(),
    ackedAt: null,
  });
}

function markMessageAcked(app, ownerId, workerId, direction, messageId) {
  const record = findRecord(app, ownerId, COLL_MESSAGE, messageRid(direction, workerId, messageId));
  if (!record) return false;
  const payload = payloadOf(record);
  if (payload.acked === true) return true;
  payload.acked = true;
  payload.ackedAt = new Date().toISOString();
  atomic.commit(app, {
    owner: record.getString("owner"),
    org: record.getString("org"),
    coll: record.getString("coll"),
    rid: record.getString("rid"),
    payload: payload,
    stamp: new Date().toISOString(),
    deleted: false,
  });
  return true;
}

routerAdd("POST", "/api/wesi/ai/workers/pairing/create", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const workerName = String(body.workerName || "").trim();
  const fingerprint = String(body.deviceFingerprint || "").trim().toLowerCase();
  const lanHint = body.lanHint == null ? null : String(body.lanHint).trim();
  const nowMs = Date.now();
  const ticket = rw.validateTicket({
    ticketId: randomId(32),
    workerId: randomId(32),
    workerName: workerName,
    deviceFingerprint: fingerprint,
    nonce: randomId(32),
    expiresAtMs: nowMs + PAIR_TTL_MS,
    lanHint: lanHint,
  }, nowMs);
  const pollSecret = randomId(64);
  const pollKey = rw.deriveRequestKey(pollSecret, $security);
  upsert(e.app, ctx.ownerId, ticket.workerId, COLL_PAIRING, ticket.ticketId, {
    ticketId: ticket.ticketId,
    workerId: ticket.workerId,
    workerName: ticket.workerName,
    deviceFingerprint: ticket.deviceFingerprint,
    nonce: ticket.nonce,
    expiresAtMs: ticket.expiresAtMs,
    lanHint: ticket.lanHint,
    ownerScope: ctx.ownerId,
    createdByEmployeeId: ctx.employeeId,
    pollKey: pollKey,
    claimedAt: null,
    credentialDeliveredAt: null,
    credentialId: null,
    revokedAt: null,
  });
  return e.json(200, {
    ok: true,
    ticket: ticket,
    pollSecret: pollSecret,
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/pairing/claim", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const ticket = rw.validateTicket(body.ticket, Date.now());
  const record = findRecord(e.app, ctx.ownerId, COLL_PAIRING, ticket.ticketId);
  if (!record) throw new BadRequestError("Wesi Worker pairing ticket не найден");
  const stored = payloadOf(record);
  if (String(stored.ownerScope || "") !== ctx.ownerId ||
      String(stored.workerId || "") !== ticket.workerId ||
      String(stored.deviceFingerprint || "") !== ticket.deviceFingerprint ||
      String(stored.nonce || "") !== ticket.nonce ||
      String(stored.revokedAt || "") || String(stored.claimedAt || "")) {
    throw new BadRequestError("Wesi Worker pairing ticket отклонён");
  }
  const expiresAtMs = Number(stored.expiresAtMs || 0);
  if (!Number.isFinite(expiresAtMs) || expiresAtMs <= Date.now()) {
    throw new BadRequestError("Wesi Worker pairing ticket истёк");
  }
  const credentialId = randomId(32);
  const issuedAt = new Date().toISOString();
  const expiresAt = new Date(Date.now() + CREDENTIAL_TTL_MS).toISOString();
  upsert(e.app, ctx.ownerId, ticket.workerId, COLL_CREDENTIAL, credentialId, {
    credentialId: credentialId,
    workerId: ticket.workerId,
    deviceFingerprint: ticket.deviceFingerprint,
    requestKey: String(stored.pollKey || ""),
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    revokedAt: null,
    pairedByEmployeeId: ctx.employeeId,
    recentNonces: [],
    lastAuthenticatedAt: null,
  });
  stored.claimedAt = new Date().toISOString();
  stored.claimedByEmployeeId = ctx.employeeId;
  stored.credentialId = credentialId;
  atomic.commit(e.app, {
    owner: record.getString("owner"),
    org: record.getString("org"),
    coll: record.getString("coll"),
    rid: record.getString("rid"),
    payload: stored,
    stamp: new Date().toISOString(),
    deleted: false,
  });
  return e.json(200, {ok: true, credentialId: credentialId, workerId: ticket.workerId});
}, $apis.requireAuth("users"));

// Desktop bootstrap poll: the high-entropy poll secret never appears in QR.
routerAdd("POST", "/api/wesi/ai/workers/pairing/poll", (e) => {
  const body = e.requestInfo().body || {};
  const ticketId = String(body.ticketId || "").trim();
  const pollSecret = String(body.pollSecret || "").trim();
  if (!/^[A-Za-z0-9_-]{20,96}$/.test(ticketId) || pollSecret.length < 32 || pollSecret.length > 256) {
    return e.json(400, {ok: false, code: "WRW_PAIRING_REJECTED"});
  }
  const record = findRecordAnyOwner(e.app, COLL_PAIRING, ticketId);
  if (!record) return e.json(404, {ok: false, code: "WRW_PAIRING_REJECTED"});
  const stored = payloadOf(record);
  const pollKey = rw.deriveRequestKey(pollSecret, $security);
  if (!rw.constantTimeEquals(String(stored.pollKey || ""), pollKey) || String(stored.revokedAt || "")) {
    return e.json(401, {ok: false, code: "WRW_PAIRING_REJECTED"});
  }
  if (Number(stored.expiresAtMs || 0) <= Date.now() && !String(stored.claimedAt || "")) {
    return e.json(410, {ok: false, code: "WRW_PAIRING_EXPIRED"});
  }
  if (!String(stored.claimedAt || "") || !String(stored.credentialId || "")) {
    return e.json(200, {ok: true, ready: false});
  }
  if (String(stored.credentialDeliveredAt || "")) {
    return e.json(409, {ok: false, code: "WRW_CREDENTIAL_ALREADY_DELIVERED"});
  }
  const credential = findRecord(e.app, record.getString("owner"), COLL_CREDENTIAL, String(stored.credentialId));
  if (!credential) return e.json(409, {ok: false, code: "WRW_PAIRING_STATE_INVALID"});
  const publicCredential = rw.publicCredentialPayload(payloadOf(credential));
  stored.credentialDeliveredAt = new Date().toISOString();
  atomic.commit(e.app, {
    owner: record.getString("owner"),
    org: record.getString("org"),
    coll: record.getString("coll"),
    rid: record.getString("rid"),
    payload: stored,
    stamp: new Date().toISOString(),
    deleted: false,
  });
  return e.json(200, {ok: true, ready: true, credential: publicCredential});
});

routerAdd("GET", "/api/wesi/ai/workers", (e) => {
  const ctx = aiContext(e);
  const rows = dataAccess.records(
    e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && deleted=false",
    "stamp",
    64,
    0,
    {owner: ctx.ownerId, coll: COLL_HEARTBEAT},
  );
  const heartbeats = [];
  const nowMs = Date.now();
  for (const row of rows) {
    const workerId = row.getString("org");
    if (!activeCredentialForWorker(e.app, ctx.ownerId, workerId, nowMs)) continue;
    const payload = payloadOf(row);
    if (payload.heartbeat && typeof payload.heartbeat === "object") heartbeats.push(payload.heartbeat);
  }
  return e.json(200, {ok: true, heartbeats: heartbeats});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/revoke", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const workerId = String(body.workerId || "").trim();
  if (!/^[A-Za-z0-9_-]{20,96}$/.test(workerId) || !ownsWorker(e.app, ctx.ownerId, workerId)) {
    throw new BadRequestError("Wesi Worker не найден");
  }
  const revokedAt = new Date().toISOString();
  for (const row of rowsForWorker(e.app, ctx.ownerId, COLL_CREDENTIAL, workerId, 32)) {
    const payload = payloadOf(row);
    if (String(payload.revokedAt || "")) continue;
    payload.revokedAt = revokedAt;
    atomic.commit(e.app, {
      owner: row.getString("owner"),
      org: row.getString("org"),
      coll: row.getString("coll"),
      rid: row.getString("rid"),
      payload: payload,
      stamp: revokedAt,
      deleted: false,
    });
  }
  return e.json(200, {ok: true, workerId: workerId, revokedAt: revokedAt});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/mailbox/enqueue", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const workerId = String(body.workerId || "").trim();
  if (!activeCredentialForWorker(e.app, ctx.ownerId, workerId, Date.now())) {
    throw new BadRequestError("Wesi Worker недоступен или отозван");
  }
  const message = rw.validateMessage(body.message);
  saveMessage(e.app, ctx.ownerId, workerId, "to_worker", message);
  return e.json(200, {ok: true, messageId: message.messageId});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/events/poll", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const workerId = String(body.workerId || "").trim();
  const limit = Math.max(1, Math.min(Number(body.limit || 16), 32));
  if (!ownsWorker(e.app, ctx.ownerId, workerId)) throw new BadRequestError("Wesi Worker не найден");
  const messages = [];
  for (const row of messageRows(e.app, ctx.ownerId, workerId)) {
    const payload = payloadOf(row);
    if (payload.direction !== "from_worker" || payload.acked === true || !payload.message) continue;
    messages.push(payload.message);
  }
  messages.sort(messageOrder);
  return e.json(200, {ok: true, messages: messages.slice(0, limit)});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/events/ack", (e) => {
  const ctx = aiContext(e);
  const body = e.requestInfo().body || {};
  const workerId = String(body.workerId || "").trim();
  const messageId = String(body.messageId || "").trim();
  if (!ownsWorker(e.app, ctx.ownerId, workerId)) throw new BadRequestError("Wesi Worker не найден");
  if (!/^[A-Za-z0-9._:-]{1,128}$/.test(messageId)) throw new BadRequestError("Некорректный messageId");
  markMessageAcked(e.app, ctx.ownerId, workerId, "from_worker", messageId);
  return e.json(200, {ok: true});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/heartbeat", (e) => {
  const auth = workerAuth(e, "/api/wesi/ai/workers/heartbeat");
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let heartbeat;
  try { heartbeat = rw.validateHeartbeat(auth.payload, auth.workerId, Date.now()); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRW_BAD_HEARTBEAT")}); }
  upsert(e.app, auth.ownerId, auth.workerId, COLL_HEARTBEAT, auth.workerId, {
    workerId: auth.workerId,
    heartbeat: heartbeat,
    lastSeenAt: new Date().toISOString(),
  });
  return e.json(200, {ok: true});
});

routerAdd("POST", "/api/wesi/ai/workers/mailbox/poll", (e) => {
  const auth = workerAuth(e, "/api/wesi/ai/workers/mailbox/poll");
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  const limit = Math.max(1, Math.min(Number(auth.payload.limit || 16), 32));
  const messages = [];
  for (const row of messageRows(e.app, auth.ownerId, auth.workerId)) {
    const payload = payloadOf(row);
    if (payload.direction !== "to_worker" || payload.acked === true || !payload.message) continue;
    messages.push(payload.message);
  }
  messages.sort(messageOrder);
  return e.json(200, {ok: true, messages: messages.slice(0, limit)});
});

routerAdd("POST", "/api/wesi/ai/workers/message", (e) => {
  const auth = workerAuth(e, "/api/wesi/ai/workers/message");
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let message;
  try { message = rw.validateMessage(auth.payload.message); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRW_BAD_JOB_MESSAGE")}); }
  saveMessage(e.app, auth.ownerId, auth.workerId, "from_worker", message);
  if (message.kind === "ack") {
    const acked = String((message.payload && message.payload.ackedMessageId) || "").trim();
    if (/^[A-Za-z0-9._:-]{1,128}$/.test(acked)) {
      markMessageAcked(e.app, auth.ownerId, auth.workerId, "to_worker", acked);
    }
  }
  return e.json(200, {ok: true, messageId: message.messageId});
});
