const handoff = require(`${__hooks}/wesi_ai_remote_media_handoff_lib.js`);
const rw = require(`${__hooks}/wesi_ai_remote_worker_lib.js`);

const COLL_HANDOFF = "ai_remote_media_handoffs";
const COLL_CREDENTIAL = "ai_remote_worker_credentials";
const COLL_MESSAGE = "ai_remote_worker_messages";
const MAX_HANDOFFS_PER_OWNER = 32;

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function findRecord(app, ownerId, coll, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: ownerId, coll: coll, rid: rid},
    );
  } catch (_) { return null; }
}

function findRecordAnyOwner(app, coll, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "coll={:coll} && rid={:rid} && deleted=false",
      {coll: coll, rid: rid},
    );
  } catch (_) { return null; }
}

function ownerHandoffs(app, ownerId) {
  try {
    return app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && deleted=false",
      "stamp",
      128,
      0,
      {owner: ownerId, coll: COLL_HANDOFF},
    );
  } catch (_) { return []; }
}

function activeOwnerHandoffCount(app, ownerId) {
  const now = Date.now();
  let count = 0;
  for (const row of ownerHandoffs(app, ownerId)) {
    const payload = payloadOf(row);
    if (Number(payload.expiresAtMs || 0) > now && String(payload.status || "") !== "consumed") count++;
  }
  return count;
}

function createRecord(app, ctx, handoffId, payload) {
  const collection = app.findCollectionByNameOrId("wesios_records");
  const record = new Record(collection);
  record.set("owner", String(ctx.ownerId || ""));
  record.set("org", "");
  record.set("coll", COLL_HANDOFF);
  record.set("rid", handoffId);
  record.set("payload", payload);
  record.set("stamp", new Date().toISOString());
  record.set("deleted", false);
  app.save(record);
  return record;
}

function savePayload(record, payload) {
  payload.updatedAt = new Date().toISOString();
  record.set("payload", payload);
  record.set("stamp", payload.updatedAt);
  record.set("org", String(payload.workerId || ""));
  $app.save(record);
  return payload;
}

function aiContext(e) {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  return ctx;
}

function canUserAccess(ctx, record) {
  if (!ctx || !record || String(record.getString("owner") || "") !== String(ctx.ownerId || "")) return false;
  if (ctx.isOwner) return true;
  const payload = payloadOf(record);
  return String(payload.employeeId || "") === String(ctx.employeeId || "");
}

function requireUserHandoff(e, ctx, id) {
  const handoffId = handoff.validateHandoffId(id);
  const record = findRecord(e.app, ctx.ownerId, COLL_HANDOFF, handoffId);
  if (!record || !canUserAccess(ctx, record)) throw new NotFoundError("Media handoff не найден");
  const payload = payloadOf(record);
  if (Number(payload.expiresAtMs || 0) <= Date.now()) {
    cleanupFiles(payload);
    record.set("deleted", true);
    record.set("stamp", new Date().toISOString());
    e.app.save(record);
    throw new NotFoundError("Media handoff истёк");
  }
  return {record: record, payload: payload};
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
  credential.set("payload", credentialPayload);
  credential.set("stamp", new Date(nowMs).toISOString());
  e.app.save(credential);
  let payload;
  try { payload = rw.parsePayloadJson(payloadJson); }
  catch (error) { return {ok: false, code: String(error.message || "WRW_BAD_PAYLOAD")}; }
  return {ok: true, ownerId: ownerId, workerId: workerId, payload: payload};
}

function workerHasAssignment(app, ownerId, workerId, jobId) {
  let rows = [];
  try {
    rows = app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && org={:worker} && deleted=false",
      "-stamp",
      256,
      0,
      {owner: ownerId, coll: COLL_MESSAGE, worker: workerId},
    );
  } catch (_) { rows = []; }
  for (const row of rows) {
    const stored = payloadOf(row);
    const message = stored.message && typeof stored.message === "object" ? stored.message : {};
    if (stored.direction === "to_worker" &&
        String(message.kind || "") === "assignment" &&
        String(message.jobId || "") === jobId) return true;
  }
  return false;
}

function requireWorkerHandoff(e, auth, id) {
  const handoffId = handoff.validateHandoffId(id);
  const record = findRecord(e.app, auth.ownerId, COLL_HANDOFF, handoffId);
  if (!record) throw new NotFoundError("Media handoff не найден");
  const payload = payloadOf(record);
  if (Number(payload.expiresAtMs || 0) <= Date.now()) throw new NotFoundError("Media handoff истёк");
  const jobId = handoff.validateJobId(auth.payload.jobId);
  if (jobId !== String(payload.jobId || "")) throw new ForbiddenError("Media handoff не принадлежит задаче");
  const assigned = workerHasAssignment(e.app, auth.ownerId, auth.workerId, jobId);
  const bound = handoff.bindWorker(payload.workerId, auth.workerId, assigned);
  if (!payload.workerId) {
    payload.workerId = bound;
    payload.boundAt = new Date().toISOString();
    savePayload(record, payload);
  }
  return {record: record, payload: payload};
}

function rootDir() {
  const root = $app.dataDir().replace(/[\\/]$/, "") + "/wesi_ai_remote_media_handoffs";
  try { $os.mkdirAll(root, 488); } catch (_) {}
  return root;
}

function chunkDir(id) {
  const handoffId = handoff.validateHandoffId(id);
  const dir = rootDir() + "/" + handoffId;
  try { $os.mkdirAll(dir, 448); } catch (_) {} // 0700
  return dir;
}

function chunkPath(id, index) {
  if (!Number.isSafeInteger(index) || index < 0 || index > handoff.MAX_CHUNKS) throw new Error("WRM_BAD_CHUNK");
  return chunkDir(id) + "/chunk-" + index + ".bin";
}

function readBytes(path) {
  const raw = $os.readFile(path);
  if (typeof raw === "string") {
    const out = [];
    for (let i = 0; i < raw.length; i++) out.push(raw.charCodeAt(i) & 255);
    return out;
  }
  return Array.from(raw || [], function(value) { return Number(value) & 255; });
}

function cleanupFiles(payload) {
  const id = String(payload.handoffId || "");
  const meta = payload.file && typeof payload.file === "object" ? payload.file : {};
  const count = Number(meta.chunkCount || 0);
  if (!/^wrm_[A-Za-z0-9_-]{20,80}$/.test(id) || !Number.isSafeInteger(count) || count < 0 || count > handoff.MAX_CHUNKS) return;
  for (let index = 0; index < count; index++) {
    try { $os.remove(chunkPath(id, index)); } catch (_) {}
  }
}

function publicState(payload) {
  const file = payload.file && typeof payload.file === "object" ? payload.file : null;
  return {
    handoffId: String(payload.handoffId || ""),
    jobId: String(payload.jobId || ""),
    direction: String(payload.direction || ""),
    status: String(payload.status || ""),
    chunkSize: handoff.CHUNK_BYTES,
    maxByteSize: Number(payload.maxByteSize || handoff.MAX_FILE_BYTES),
    expiresAt: new Date(Number(payload.expiresAtMs || 0)).toISOString(),
    file: file ? {
      name: String(file.name || ""),
      mimeType: String(file.mimeType || ""),
      byteSize: Number(file.byteSize || 0),
      sha256: String(file.sha256 || ""),
      chunkSize: Number(file.chunkSize || handoff.CHUNK_BYTES),
      chunkCount: Number(file.chunkCount || 0),
    } : null,
  };
}

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs", (e) => {
  const ctx = aiContext(e);
  if (activeOwnerHandoffCount(e.app, ctx.ownerId) >= MAX_HANDOFFS_PER_OWNER) {
    return e.json(429, {ok: false, code: "WRM_CAPACITY"});
  }
  const body = e.requestInfo().body || {};
  let jobId;
  try { jobId = handoff.validateJobId(body.jobId); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_JOB_ID")}); }
  const direction = String(body.direction || "").trim();
  if (direction !== "input" && direction !== "output") return e.json(400, {ok: false, code: "WRM_BAD_DIRECTION"});
  const now = Date.now();
  const id = "wrm_" + $security.randomString(32);
  const payload = {
    v: 1,
    handoffId: id,
    jobId: jobId,
    employeeId: String(ctx.employeeId || ""),
    direction: direction,
    workerId: "",
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    expiresAtMs: now + handoff.HANDOFF_TTL_MS,
    status: direction === "input" ? "uploading" : "awaiting_worker",
    maxByteSize: handoff.MAX_FILE_BYTES,
    received: {},
    file: null,
  };
  try {
    if (direction === "input") {
      payload.file = handoff.normalizeFileMeta(body.file || body);
    } else {
      const maxByteSize = Number(body.maxByteSize || handoff.MAX_FILE_BYTES);
      if (!Number.isSafeInteger(maxByteSize) || maxByteSize <= 0 || maxByteSize > handoff.MAX_FILE_BYTES) {
        return e.json(400, {ok: false, code: "WRM_FILE_SIZE_INVALID"});
      }
      payload.maxByteSize = maxByteSize;
    }
  } catch (error) {
    return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_FILE_META")});
  }
  createRecord(e.app, ctx, id, payload);
  return e.json(200, {ok: true, handoff: publicState(payload)});
}, $apis.requireAuth("users"));

routerAdd("PUT", "/api/wesi/ai/workers/media-handoffs/{id}/chunks/{index}", (e) => {
  const ctx = aiContext(e);
  let state;
  try { state = requireUserHandoff(e, ctx, e.request.pathValue("id")); }
  catch (error) { throw error; }
  const payload = state.payload;
  if (payload.direction !== "input" || payload.status !== "uploading" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  const index = Number(e.request.pathValue("index"));
  let expected;
  try { expected = handoff.expectedChunkBytes(payload.file, index); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_CHUNK")}); }
  let bytes;
  try { bytes = toBytes(e.request.body, expected + 1); }
  catch (_) { return e.json(413, {ok: false, code: "WRM_BAD_CHUNK"}); }
  if (!bytes || Number(bytes.length || 0) !== expected) return e.json(400, {ok: false, code: "WRM_CHUNK_SIZE_MISMATCH"});
  try { $os.writeFile(chunkPath(payload.handoffId, index), bytes, 384); } // 0600
  catch (_) { return e.json(500, {ok: false, code: "WRM_STORAGE_FAILED"}); }
  payload.received[String(index)] = true;
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {ok: true, index: index});
}, $apis.requireAuth("users"), $apis.bodyLimit(handoff.CHUNK_BYTES + 65536));

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs/{id}/complete", (e) => {
  const ctx = aiContext(e);
  const state = requireUserHandoff(e, ctx, e.request.pathValue("id"));
  const payload = state.payload;
  if (payload.direction !== "input" || payload.status !== "uploading" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  for (let index = 0; index < payload.file.chunkCount; index++) {
    if (payload.received[String(index)] !== true) return e.json(409, {ok: false, code: "WRM_UPLOAD_INCOMPLETE"});
  }
  payload.status = "ready";
  payload.completedAt = new Date().toISOString();
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {ok: true, handoff: publicState(payload)});
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/ai/workers/media-handoffs/{id}", (e) => {
  const ctx = aiContext(e);
  const state = requireUserHandoff(e, ctx, e.request.pathValue("id"));
  return e.json(200, {ok: true, handoff: publicState(state.payload)});
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/ai/workers/media-handoffs/{id}/chunks/{index}", (e) => {
  const ctx = aiContext(e);
  const state = requireUserHandoff(e, ctx, e.request.pathValue("id"));
  const payload = state.payload;
  if (payload.direction !== "output" || payload.status !== "ready" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  const index = Number(e.request.pathValue("index"));
  let expected;
  try { expected = handoff.expectedChunkBytes(payload.file, index); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_CHUNK")}); }
  let bytes;
  try { bytes = readBytes(chunkPath(payload.handoffId, index)); }
  catch (_) { return e.json(404, {ok: false, code: "WRM_CHUNK_MISSING"}); }
  if (bytes.length !== expected) return e.json(409, {ok: false, code: "WRM_CHUNK_SIZE_MISMATCH"});
  return e.json(200, {ok: true, index: index, dataBase64: handoff.base64Encode(bytes)});
}, $apis.requireAuth("users"));

routerAdd("DELETE", "/api/wesi/ai/workers/media-handoffs/{id}", (e) => {
  const ctx = aiContext(e);
  const state = requireUserHandoff(e, ctx, e.request.pathValue("id"));
  cleanupFiles(state.payload);
  state.record.set("deleted", true);
  state.record.set("stamp", new Date().toISOString());
  e.app.save(state.record);
  return e.json(200, {ok: true});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs/{id}/worker/input/{index}", (e) => {
  const id = String(e.request.pathValue("id") || "");
  const index = Number(e.request.pathValue("index"));
  const path = "/api/wesi/ai/workers/media-handoffs/" + id + "/worker/input/" + index;
  const auth = workerAuth(e, path);
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let state;
  try { state = requireWorkerHandoff(e, auth, id); }
  catch (error) { return e.json(403, {ok: false, code: String(error.message || "WRM_WORKER_FORBIDDEN")}); }
  const payload = state.payload;
  if (payload.direction !== "input" || payload.status !== "ready" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  let expected;
  try { expected = handoff.expectedChunkBytes(payload.file, index); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_CHUNK")}); }
  let bytes;
  try { bytes = readBytes(chunkPath(id, index)); }
  catch (_) { return e.json(404, {ok: false, code: "WRM_CHUNK_MISSING"}); }
  if (bytes.length !== expected) return e.json(409, {ok: false, code: "WRM_CHUNK_SIZE_MISMATCH"});
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {
    ok: true,
    handoff: publicState(payload),
    index: index,
    dataBase64: handoff.base64Encode(bytes),
  });
}, $apis.bodyLimit(640 * 1024));

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs/{id}/worker/output/start", (e) => {
  const id = String(e.request.pathValue("id") || "");
  const path = "/api/wesi/ai/workers/media-handoffs/" + id + "/worker/output/start";
  const auth = workerAuth(e, path);
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let state;
  try { state = requireWorkerHandoff(e, auth, id); }
  catch (error) { return e.json(403, {ok: false, code: String(error.message || "WRM_WORKER_FORBIDDEN")}); }
  const payload = state.payload;
  if (payload.direction !== "output" || payload.status !== "awaiting_worker") {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  let meta;
  try { meta = handoff.normalizeFileMeta(auth.payload.file || auth.payload, {maxBytes: payload.maxByteSize}); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_FILE_META")}); }
  payload.file = meta;
  payload.received = {};
  payload.status = "uploading";
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {ok: true, handoff: publicState(payload)});
}, $apis.bodyLimit(640 * 1024));

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs/{id}/worker/output/chunk", (e) => {
  const id = String(e.request.pathValue("id") || "");
  const path = "/api/wesi/ai/workers/media-handoffs/" + id + "/worker/output/chunk";
  const auth = workerAuth(e, path);
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let state;
  try { state = requireWorkerHandoff(e, auth, id); }
  catch (error) { return e.json(403, {ok: false, code: String(error.message || "WRM_WORKER_FORBIDDEN")}); }
  const payload = state.payload;
  if (payload.direction !== "output" || payload.status !== "uploading" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  const index = Number(auth.payload.index);
  let expected;
  try { expected = handoff.expectedChunkBytes(payload.file, index); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_CHUNK")}); }
  let bytes;
  try { bytes = handoff.base64Decode(auth.payload.dataBase64, handoff.CHUNK_BYTES); }
  catch (error) { return e.json(400, {ok: false, code: String(error.message || "WRM_BAD_BASE64")}); }
  if (bytes.length !== expected) return e.json(400, {ok: false, code: "WRM_CHUNK_SIZE_MISMATCH"});
  try { $os.writeFile(chunkPath(id, index), bytes, 384); }
  catch (_) { return e.json(500, {ok: false, code: "WRM_STORAGE_FAILED"}); }
  payload.received[String(index)] = true;
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {ok: true, index: index});
}, $apis.bodyLimit(640 * 1024));

routerAdd("POST", "/api/wesi/ai/workers/media-handoffs/{id}/worker/output/complete", (e) => {
  const id = String(e.request.pathValue("id") || "");
  const path = "/api/wesi/ai/workers/media-handoffs/" + id + "/worker/output/complete";
  const auth = workerAuth(e, path);
  if (!auth.ok) return e.json(401, {ok: false, code: auth.code});
  let state;
  try { state = requireWorkerHandoff(e, auth, id); }
  catch (error) { return e.json(403, {ok: false, code: String(error.message || "WRM_WORKER_FORBIDDEN")}); }
  const payload = state.payload;
  if (payload.direction !== "output" || payload.status !== "uploading" || !payload.file) {
    return e.json(409, {ok: false, code: "WRM_HANDOFF_STATE_INVALID"});
  }
  for (let index = 0; index < payload.file.chunkCount; index++) {
    if (payload.received[String(index)] !== true) return e.json(409, {ok: false, code: "WRM_UPLOAD_INCOMPLETE"});
  }
  payload.status = "ready";
  payload.completedAt = new Date().toISOString();
  payload.expiresAtMs = Date.now() + handoff.HANDOFF_TTL_MS;
  savePayload(state.record, payload);
  return e.json(200, {ok: true, handoff: publicState(payload)});
}, $apis.bodyLimit(640 * 1024));
