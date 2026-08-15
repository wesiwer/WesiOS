const GITHUB_COLL = "ai_github_connector";
const DEVICE_TTL_CAP_MS = 20 * 60 * 1000;

function ghText(value) { return String(value == null ? "" : value).trim(); }
function ghLib() { return require(`${__hooks}/wesi_ai_github_lib.js`); }
function ghAi() { return require(`${__hooks}/wesi_ai_lib.js`); }

function ghContext(e) {
  const ai = ghAi();
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  return ctx;
}

function ghEncryptionKey() {
  const key = ghText($os.getenv("WESI_GITHUB_CONNECTOR_KEY"));
  if (key.length !== 32) throw new BadRequestError("GitHub connector не настроен: отсутствует encryption key");
  return key;
}

function ghClientId() {
  const clientId = ghText($os.getenv("WESI_GITHUB_OAUTH_CLIENT_ID"));
  if (!/^[A-Za-z0-9_-]{10,160}$/.test(clientId)) throw new BadRequestError("GitHub connector не настроен: отсутствует OAuth client id");
  return clientId;
}

function ghPayload(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function ghCollection(e) { return e.app.findCollectionByNameOrId("wesios_records"); }
function ghFind(e, owner, rid) {
  try {
    return e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: owner, coll: GITHUB_COLL, rid: rid},
    );
  } catch (_) { return null; }
}

function ghCreate(e, owner, rid, payload) {
  const record = new Record(ghCollection(e));
  record.set("owner", owner);
  record.set("org", "wesi-ai");
  record.set("coll", GITHUB_COLL);
  record.set("rid", rid);
  record.set("payload", payload);
  record.set("stamp", new Date().toISOString());
  record.set("deleted", false);
  e.app.save(record);
  return record;
}

function ghSave(e, record, payload) {
  record.set("payload", payload);
  record.set("stamp", new Date().toISOString());
  record.set("deleted", false);
  e.app.save(record);
  return record;
}

function ghDelete(e, record) {
  if (!record) return;
  record.set("deleted", true);
  record.set("stamp", new Date().toISOString());
  e.app.save(record);
}

function ghEncrypt(value) { return String($security.encrypt(String(value), ghEncryptionKey())); }
function ghDecrypt(value) { return String($security.decrypt(String(value), ghEncryptionKey())); }

function ghForm(values) {
  return Object.keys(values).map((key) => encodeURIComponent(key) + "=" + encodeURIComponent(String(values[key]))).join("&");
}

function ghPostForm(url, values) {
  return $http.send({
    url: url,
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": "WesiOS-GitHub-Connector/1",
    },
    body: ghForm(values),
    timeout: 15,
  });
}

function ghGithubGet(path, token) {
  const lib = ghLib();
  return $http.send({
    url: lib.apiUrl(path),
    method: "GET",
    headers: lib.safeHeaders(token),
    timeout: 15,
  });
}

function ghStatusCode(response) {
  return Number(response && (response.statusCode != null ? response.statusCode : response.status)) || 0;
}

function ghCredential(e, owner) { return ghFind(e, owner, "github:credential"); }

routerAdd("POST", "/api/wesi/ai/connectors/github/start", (e) => {
  const ctx = ghContext(e);
  const lib = ghLib();
  const clientId = ghClientId();
  ghEncryptionKey();
  const response = ghPostForm(lib.DEVICE_CODE_URL, {
    client_id: clientId,
    scope: lib.DEFAULT_SCOPES.join(" "),
  });
  if (ghStatusCode(response) < 200 || ghStatusCode(response) >= 300) {
    throw new BadRequestError("GitHub OAuth временно недоступен");
  }
  const data = lib.parseJsonResponse(response);
  const deviceCode = ghText(data.device_code);
  const userCode = ghText(data.user_code);
  const verificationUri = ghText(data.verification_uri);
  const expiresIn = Math.max(60, Math.min(Number(data.expires_in || 900), 1200));
  const interval = Math.max(5, Math.min(Number(data.interval || 5), 60));
  if (!deviceCode || deviceCode.length > 512 || !/^[A-Z0-9-]{4,32}$/i.test(userCode) || verificationUri !== "https://github.com/login/device") {
    throw new BadRequestError("GitHub OAuth вернул некорректный Device Flow ответ");
  }
  const now = Date.now();
  const sessionId = $security.randomString(36);
  const existing = ghCredential(e, ctx.ownerId);
  if (existing) ghDelete(e, existing);
  ghCreate(e, ctx.ownerId, "github:device:" + sessionId, {
    kind: "device",
    sessionId: sessionId,
    deviceCodeCiphertext: ghEncrypt(deviceCode),
    userCode: userCode,
    verificationUri: verificationUri,
    intervalSec: interval,
    nextPollAtMs: now + interval * 1000,
    expiresAtMs: Math.min(now + expiresIn * 1000, now + DEVICE_TTL_CAP_MS),
    createdAt: new Date(now).toISOString(),
  });
  return e.json(200, {
    ok: true,
    sessionId: sessionId,
    userCode: userCode,
    verificationUri: verificationUri,
    expiresIn: expiresIn,
    interval: interval,
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/connectors/github/poll", (e) => {
  const ctx = ghContext(e);
  const lib = ghLib();
  const body = e.requestInfo().body || {};
  const sessionId = ghText(body.sessionId);
  if (!/^[A-Za-z0-9_-]{20,96}$/.test(sessionId)) throw new BadRequestError("Некорректная GitHub OAuth session");
  const record = ghFind(e, ctx.ownerId, "github:device:" + sessionId);
  if (!record) throw new BadRequestError("GitHub OAuth session не найдена");
  const state = ghPayload(record);
  const now = Date.now();
  if (Number(state.expiresAtMs) <= now) {
    ghDelete(e, record);
    return e.json(410, {ok: false, code: "expired_token"});
  }
  if (Number(state.nextPollAtMs || 0) > now) {
    return e.json(429, {ok: false, code: "poll_too_fast", retryAfterMs: Number(state.nextPollAtMs) - now});
  }
  let deviceCode;
  try { deviceCode = ghDecrypt(state.deviceCodeCiphertext); }
  catch (_) { throw new BadRequestError("GitHub OAuth session повреждена"); }
  const response = ghPostForm(lib.ACCESS_TOKEN_URL, {
    client_id: ghClientId(),
    device_code: deviceCode,
    grant_type: "urn:ietf:params:oauth:grant-type:device_code",
  });
  const data = lib.parseJsonResponse(response);
  const error = ghText(data.error);
  if (error === "authorization_pending" || error === "slow_down") {
    const extra = error === "slow_down" ? 5 : 0;
    state.intervalSec = Math.max(5, Math.min(Number(state.intervalSec || 5) + extra, 60));
    state.nextPollAtMs = now + state.intervalSec * 1000;
    ghSave(e, record, state);
    return e.json(202, {ok: true, ready: false, interval: state.intervalSec});
  }
  if (error === "expired_token" || error === "access_denied") {
    ghDelete(e, record);
    return e.json(400, {ok: false, code: error});
  }
  const token = ghText(data.access_token);
  const tokenType = ghText(data.token_type).toLowerCase();
  const scopes = lib.uniqueScopes(data.scope);
  if (token.length < 20 || token.length > 512 || (tokenType && tokenType !== "bearer")) {
    throw new BadRequestError("GitHub OAuth не вернул валидный access token");
  }
  const userResponse = ghGithubGet("/user", token);
  if (ghStatusCode(userResponse) < 200 || ghStatusCode(userResponse) >= 300) {
    throw new BadRequestError("Не удалось проверить GitHub credential");
  }
  const user = lib.parseJsonResponse(userResponse);
  const login = ghText(user.login);
  if (!/^[A-Za-z0-9-]{1,80}$/.test(login)) throw new BadRequestError("GitHub credential не принадлежит валидному пользователю");
  const previous = ghCredential(e, ctx.ownerId);
  if (previous) ghDelete(e, previous);
  ghCreate(e, ctx.ownerId, "github:credential", {
    kind: "credential",
    tokenCiphertext: ghEncrypt(token),
    tokenType: "bearer",
    scopes: scopes,
    login: login,
    githubUserId: String(user.id || ""),
    connectedAt: new Date(now).toISOString(),
    revokedAt: null,
  });
  ghDelete(e, record);
  return e.json(200, {ok: true, ready: true, connected: true, login: login, scopes: scopes});
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/ai/connectors/github/status", (e) => {
  const ctx = ghContext(e);
  const credential = ghCredential(e, ctx.ownerId);
  if (!credential) return e.json(200, {ok: true, connected: false});
  const payload = ghPayload(credential);
  return e.json(200, {
    ok: true,
    connected: true,
    login: ghText(payload.login),
    scopes: ghLib().uniqueScopes(payload.scopes),
    connectedAt: ghText(payload.connectedAt) || null,
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/connectors/github/disconnect", (e) => {
  const ctx = ghContext(e);
  const credential = ghCredential(e, ctx.ownerId);
  if (credential) ghDelete(e, credential);
  return e.json(200, {ok: true, connected: false});
}, $apis.requireAuth("users"));