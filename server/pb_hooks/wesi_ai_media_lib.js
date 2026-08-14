const PUBLIC_BASE = "https://api.wesi-inc.ru";
const STORAGE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_FILE_BYTES = 128 * 1024 * 1024;

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function safeText(value, max) {
  const text = String(value == null ? "" : value).trim();
  return text.length <= max ? text : text.slice(0, max);
}

function safeJobId(value) {
  const id = String(value || "").trim();
  return /^wam_[A-Za-z0-9]{24,64}$/.test(id) ? id : "";
}

function fileExtension(mimeType, kind) {
  const mime = String(mimeType || "").split(";")[0].trim().toLowerCase();
  const known = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/webp": "webp",
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/ogg": "ogg",
    "audio/flac": "flac",
    "video/mp4": "mp4",
    "video/webm": "webm"
  };
  if (known[mime]) return known[mime];
  if (kind === "image") return "bin";
  if (kind === "music" || kind === "audio") return "bin";
  if (kind === "video") return "bin";
  return "bin";
}

function allowedMime(kind, mimeType) {
  const mime = String(mimeType || "").split(";")[0].trim().toLowerCase();
  if (kind === "image") return /^image\/(png|jpeg|webp)$/.test(mime);
  if (kind === "music" || kind === "audio") return /^audio\/(mpeg|mp3|wav|x-wav|ogg|flac)$/.test(mime);
  if (kind === "video") return /^video\/(mp4|webm)$/.test(mime);
  return false;
}

function rootDir() {
  const dir = $app.dataDir().replace(/\/$/, "") + "/wesi_ai_media";
  $os.mkdirAll(dir, 488); // 0750
  return dir;
}

function mediaUrl(jobId, token) {
  return PUBLIC_BASE + "/api/wesi/ai/media/file/" + encodeURIComponent(jobId) + "?token=" + encodeURIComponent(token);
}

function makeContentBlock(payload) {
  const status = String(payload.status || "pending");
  const data = {
    mediaType: String(payload.kind || ""),
    title: safeText(payload.title, 240),
    prompt: safeText(payload.prompt, 2000),
    status: status,
    jobId: String(payload.jobId || "")
  };
  if (status === "ready" && payload.fileToken) {
    data.url = mediaUrl(payload.jobId, payload.fileToken);
    data.mimeType = String(payload.mimeType || "");
  }
  return {type: "media", data: data};
}

function createJob(ctx, kind, prompt, title, extra) {
  const jobId = "wam_" + $security.randomString(28);
  const collection = $app.findCollectionByNameOrId("wesios_records");
  const record = new Record(collection);
  const now = new Date().toISOString();
  const payload = Object.assign({
    jobId: jobId,
    employeeId: String(ctx.employeeId || ""),
    kind: kind,
    title: safeText(title, 240),
    prompt: safeText(prompt, 12000),
    status: "pending",
    createdAt: now,
    updatedAt: now
  }, extra && typeof extra === "object" ? extra : {});
  record.set("owner", String(ctx.ownerId || ""));
  record.set("org", "");
  record.set("coll", "ai_media");
  record.set("rid", "media:" + jobId);
  record.set("payload", payload);
  record.set("stamp", now);
  record.set("deleted", false);
  $app.save(record);
  return record;
}

function savePayload(record, payload) {
  const now = new Date().toISOString();
  payload.updatedAt = now;
  record.set("payload", payload);
  record.set("stamp", now);
  $app.save(record);
  return payload;
}

function failJob(record, code) {
  const payload = payloadOf(record);
  payload.status = "failed";
  payload.errorCode = safeText(code || "WAI_MEDIA_JOB_FAILED", 120);
  payload.failedAt = new Date().toISOString();
  savePayload(record, payload);
  return payload;
}

function findJob(jobId) {
  const id = safeJobId(jobId);
  if (!id) return null;
  try {
    return $app.findFirstRecordByFilter(
      "wesios_records",
      "coll='ai_media' && rid={:rid} && deleted=false",
      {rid: "media:" + id}
    );
  } catch (_) {
    return null;
  }
}

function canAccess(ctx, record) {
  if (!ctx || !record) return false;
  if (String(record.getString("owner") || "") !== String(ctx.ownerId || "")) return false;
  if (ctx.isOwner) return true;
  const payload = payloadOf(record);
  return String(payload.employeeId || "") === String(ctx.employeeId || "");
}

function persistRelayArtifact(ai, cfg, record, relayMedia) {
  const payload = payloadOf(record);
  const kind = String(payload.kind || "");
  const artifactId = String(relayMedia && relayMedia.relayArtifactId || "");
  if (!artifactId) return {ok: false, code: "WAI_RELAY_BAD_ARTIFACT"};
  const fetched = ai.fetchRelayArtifact(cfg, artifactId);
  if (!fetched.ok) return fetched;
  const bytes = fetched.bytes;
  const mimeType = String(fetched.mimeType || relayMedia.mimeType || "");
  if (!Array.isArray(bytes) || !bytes.length || bytes.length > MAX_FILE_BYTES || !allowedMime(kind, mimeType)) {
    return {ok: false, code: "WAI_RELAY_BAD_ARTIFACT"};
  }
  if (relayMedia.byteSize && Number(relayMedia.byteSize) !== bytes.length) {
    return {ok: false, code: "WAI_RELAY_BAD_ARTIFACT"};
  }

  const ext = fileExtension(mimeType, kind);
  const filename = payload.jobId + "." + ext;
  const path = rootDir() + "/" + filename;
  try {
    $os.writeFile(path, bytes, 416); // 0640
  } catch (_) {
    return {ok: false, code: "WAI_MEDIA_STORAGE_FAILED"};
  }

  payload.status = "ready";
  payload.mimeType = mimeType;
  payload.byteSize = bytes.length;
  payload.filename = filename;
  payload.fileToken = $security.randomString(48);
  payload.readyAt = new Date().toISOString();
  payload.expiresAt = new Date(Date.now() + STORAGE_TTL_MS).toISOString();
  delete payload.errorCode;
  savePayload(record, payload);
  return {ok: true, payload: payload, contentBlock: makeContentBlock(payload)};
}

function serveFile(e, jobId, token) {
  const record = findJob(jobId);
  if (!record) throw new NotFoundError("Медиафайл не найден");
  const payload = payloadOf(record);
  const expected = String(payload.fileToken || "");
  const supplied = String(token || "");
  if (!expected || !supplied || !$security.equal(expected, supplied)) {
    throw new NotFoundError("Медиафайл не найден");
  }
  if (String(payload.status || "") !== "ready") throw new NotFoundError("Медиафайл не готов");
  const expires = Date.parse(String(payload.expiresAt || ""));
  if (!Number.isFinite(expires) || expires <= Date.now()) throw new NotFoundError("Ссылка на медиафайл истекла");
  const filename = String(payload.filename || "");
  if (!/^wam_[A-Za-z0-9]{24,64}\.(png|jpg|webp|mp3|wav|ogg|flac|mp4|webm|bin)$/.test(filename)) {
    throw new NotFoundError("Медиафайл не найден");
  }
  const mimeType = String(payload.mimeType || "application/octet-stream");
  e.response.header().set("Content-Type", mimeType);
  e.response.header().set("Cache-Control", "private, max-age=3600");
  e.response.header().set("X-Content-Type-Options", "nosniff");
  return e.fileFS($os.dirFS(rootDir()), filename);
}

module.exports = {
  payloadOf: payloadOf,
  safeText: safeText,
  safeJobId: safeJobId,
  createJob: createJob,
  savePayload: savePayload,
  failJob: failJob,
  findJob: findJob,
  canAccess: canAccess,
  persistRelayArtifact: persistRelayArtifact,
  makeContentBlock: makeContentBlock,
  serveFile: serveFile,
  mediaUrl: mediaUrl
};
