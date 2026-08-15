const WAI_UPLOAD_CHUNK_BYTES = 1024 * 1024;
const WAI_UPLOAD_MAX_FILE_BYTES = 256 * 1024 * 1024;
const WAI_UPLOAD_META_TTL_MS = 70 * 60 * 1000;
const WAI_UPLOAD_ID_RE = /^[A-Za-z0-9_-]{20,96}$/;

function waiUploadRoot() {
  const root = $os.tempDir().replace(/[\\/]$/, "") + "/wesi-ai-upload-meta-v1";
  try { $os.mkdirAll(root, 0o700); } catch (_) {}
  return root;
}

function waiUploadMetaPath(id) {
  if (!WAI_UPLOAD_ID_RE.test(String(id || ""))) throw new BadRequestError("Некорректная сессия загрузки");
  return waiUploadRoot() + "/" + id + ".json";
}

function waiUploadReadMeta(id) {
  let raw;
  try { raw = $os.readFile(waiUploadMetaPath(id)); } catch (_) { throw new NotFoundError("Сессия загрузки не найдена"); }
  const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
  let meta;
  try { meta = JSON.parse(text); } catch (_) { throw new BadRequestError("Сессия загрузки повреждена"); }
  if (!meta || meta.id !== id || Number(meta.expiresAt || 0) <= Date.now()) {
    try { $os.remove(waiUploadMetaPath(id)); } catch (_) {}
    throw new BadRequestError("Сессия загрузки истекла");
  }
  return meta;
}

function waiUploadWriteMeta(meta) {
  $os.writeFile(waiUploadMetaPath(meta.id), JSON.stringify(meta), 0o600);
}

function waiUploadDeleteMeta(id) {
  try { $os.remove(waiUploadMetaPath(id)); } catch (_) {}
}

function waiUploadScope(ctx) {
  return String(ctx.ownerId || "") + ":" + String(ctx.employeeId || "");
}

function waiUploadRequireOwner(meta, ctx) {
  if (String(meta.scope || "") !== waiUploadScope(ctx)) throw new ForbiddenError("Чужая сессия загрузки");
}

function waiBase64Encode(bytes) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const a = Number(bytes[i] || 0) & 255;
    const hasB = i + 1 < bytes.length;
    const hasC = i + 2 < bytes.length;
    const b = hasB ? Number(bytes[i + 1] || 0) & 255 : 0;
    const c = hasC ? Number(bytes[i + 2] || 0) & 255 : 0;
    out += alphabet[(a >> 2) & 63];
    out += alphabet[((a & 3) << 4) | ((b >> 4) & 15)];
    out += hasB ? alphabet[((b & 15) << 2) | ((c >> 6) & 3)] : "=";
    out += hasC ? alphabet[c & 63] : "=";
  }
  return out;
}

function waiRelayUploadCall(ai, cfg, operation, input, suffix) {
  const requestId = "wai_upload_" + Date.now() + "_" + $security.randomString(12) + "_" + suffix;
  return ai.callRelayJson(cfg, {
    requestId: requestId,
    route: "wesi/fast",
    operation: operation,
    input: input
  }, requestId, 90);
}

function waiRelayCode(relay, fallback) {
  return relay && relay.code ? String(relay.code) : fallback;
}

routerAdd("POST", "/api/wesi/ai/uploads", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  let name = String(body.name || "file").replace(/[\\/\x00-\x1f\x7f]/g, "_").trim();
  if (!name) name = "file";
  if (name.length > 180) name = name.slice(name.length - 180);
  const mimeType = String(body.mimeType || "application/octet-stream").trim().toLowerCase();
  const byteSize = Number(body.byteSize || 0);
  if (!/^[a-z0-9!#$&^_.+\-]+\/[a-z0-9!#$&^_.+\-]+$/i.test(mimeType) || mimeType.length > 120) {
    return e.json(400, {ok: false, code: "WAI_UPLOAD_INVALID"});
  }
  if (!Number.isSafeInteger(byteSize) || byteSize <= 0 || byteSize > WAI_UPLOAD_MAX_FILE_BYTES) {
    return e.json(413, {ok: false, code: "WAI_UPLOAD_TOO_LARGE"});
  }
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  const relay = waiRelayUploadCall(ai, cfg, "attachment.upload.start", {
    name: name,
    mimeType: mimeType,
    byteSize: byteSize
  }, "start");
  if (!relay.ok) return e.json(relay.status || 502, {ok: false, code: waiRelayCode(relay, "WAI_UPLOAD_FAILED")});
  const upload = relay.result && relay.result.upload && typeof relay.result.upload === "object" ? relay.result.upload : {};
  const id = String(upload.id || "");
  const chunkSize = Number(upload.chunkSize || WAI_UPLOAD_CHUNK_BYTES);
  const chunkCount = Number(upload.chunkCount || 0);
  if (!WAI_UPLOAD_ID_RE.test(id) || chunkSize !== WAI_UPLOAD_CHUNK_BYTES || !Number.isSafeInteger(chunkCount) || chunkCount <= 0 || chunkCount > 256) {
    return e.json(502, {ok: false, code: "WAI_UPLOAD_BAD_RESPONSE"});
  }
  const meta = {
    v: 1,
    id: id,
    scope: waiUploadScope(ctx),
    name: name,
    mimeType: mimeType,
    byteSize: byteSize,
    chunkSize: chunkSize,
    chunkCount: chunkCount,
    received: {},
    createdAt: Date.now(),
    expiresAt: Date.now() + WAI_UPLOAD_META_TTL_MS
  };
  try { waiUploadWriteMeta(meta); } catch (_) {
    waiRelayUploadCall(ai, cfg, "attachment.upload.cancel", {uploadId: id}, "rollback");
    return e.json(500, {ok: false, code: "WAI_UPLOAD_FAILED"});
  }
  return e.json(200, {
    ok: true,
    uploadId: id,
    chunkSize: chunkSize,
    chunkCount: chunkCount,
    expiresAt: new Date(meta.expiresAt).toISOString()
  });
}, $apis.requireAuth("users"));

routerAdd("PUT", "/api/wesi/ai/uploads/{id}/chunks/{index}", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const id = String(e.request.pathValue("id") || "");
  const meta = waiUploadReadMeta(id);
  waiUploadRequireOwner(meta, ctx);
  const index = Number(e.request.pathValue("index"));
  if (!Number.isSafeInteger(index) || index < 0 || index >= meta.chunkCount) {
    return e.json(400, {ok: false, code: "WAI_UPLOAD_BAD_CHUNK"});
  }
  const expected = Math.min(meta.chunkSize, meta.byteSize - index * meta.chunkSize);
  let bytes;
  try { bytes = toBytes(e.request.body, expected + 1); } catch (_) {
    return e.json(413, {ok: false, code: "WAI_UPLOAD_BAD_CHUNK"});
  }
  if (!bytes || typeof bytes.length !== "number" || bytes.length !== expected) {
    return e.json(400, {ok: false, code: "WAI_UPLOAD_CHUNK_MISMATCH"});
  }
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  const relay = waiRelayUploadCall(ai, cfg, "attachment.upload.chunk", {
    uploadId: id,
    index: index,
    dataBase64: waiBase64Encode(bytes)
  }, "chunk" + index);
  if (!relay.ok) return e.json(relay.status || 502, {ok: false, code: waiRelayCode(relay, "WAI_UPLOAD_FAILED")});
  meta.received[String(index)] = true;
  meta.expiresAt = Date.now() + WAI_UPLOAD_META_TTL_MS;
  waiUploadWriteMeta(meta);
  return e.json(200, {ok: true, index: index});
}, $apis.requireAuth("users"), $apis.bodyLimit(WAI_UPLOAD_CHUNK_BYTES + 65536));

routerAdd("POST", "/api/wesi/ai/uploads/{id}/complete", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const id = String(e.request.pathValue("id") || "");
  const meta = waiUploadReadMeta(id);
  waiUploadRequireOwner(meta, ctx);
  for (let index = 0; index < meta.chunkCount; index++) {
    if (meta.received[String(index)] !== true) return e.json(409, {ok: false, code: "WAI_UPLOAD_INCOMPLETE"});
  }
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  const relay = waiRelayUploadCall(ai, cfg, "attachment.upload.complete", {uploadId: id}, "complete");
  if (!relay.ok) return e.json(relay.status || 502, {ok: false, code: waiRelayCode(relay, "WAI_UPLOAD_FAILED")});
  const attachment = relay.result && relay.result.transportAttachment && typeof relay.result.transportAttachment === "object"
    ? relay.result.transportAttachment
    : null;
  if (!attachment || String(attachment.mimeType || "") !== "application/x-wesi-upload-ref" || !String(attachment.dataBase64 || "")) {
    return e.json(502, {ok: false, code: "WAI_UPLOAD_BAD_RESPONSE"});
  }
  waiUploadDeleteMeta(id);
  return e.json(200, {ok: true, transportAttachment: attachment});
}, $apis.requireAuth("users"));

routerAdd("DELETE", "/api/wesi/ai/uploads/{id}", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const id = String(e.request.pathValue("id") || "");
  let meta = null;
  try { meta = waiUploadReadMeta(id); } catch (_) {}
  if (meta) waiUploadRequireOwner(meta, ctx);
  const cfg = ai.readRelayConfig();
  if (cfg.ready && WAI_UPLOAD_ID_RE.test(id)) {
    waiRelayUploadCall(ai, cfg, "attachment.upload.cancel", {uploadId: id}, "cancel");
  }
  waiUploadDeleteMeta(id);
  return e.json(200, {ok: true});
}, $apis.requireAuth("users"));
