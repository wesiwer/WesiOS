routerAdd("GET", "/api/wesi/security/version", (e) => {
  let jsonReadable = false;
  try {
    const records = e.app.findRecordsByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security'",
      "-stamp",
      1,
      0,
    );
    if (records.length > 0) {
      const model = new DynamicModel({"kind": ""});
      records[0].unmarshalJSONField("payload", model);
      jsonReadable = Boolean(String(model.kind || ""));
    }
  } catch (_) {}
  return e.json(jsonReadable ? 200 : 503, {
    "version": "2026-08-09.security-json-v4",
    "jsonReadable": jsonReadable,
  });
});

/// WesiOS second-factor authentication and revocable sessions.
///
/// PocketBase auth tokens are stateless. WesiOS therefore requires a second,
/// server-side session id (`X-WesiOS-Session`) for every protected application
/// request. Revoking that session immediately cuts access even while the
/// underlying PocketBase token has not expired yet.

routerUse((e) => {
  const path = e.request.url.path || "";
  const method = String(e.request.method || "GET").toUpperCase();

  const body = () => {
    try { return e.requestInfo().body || {}; } catch (_) { return {}; }
  };
  const validEmail = (value) => {
    const email = String(value || "").trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith("@wesi.local");
  };
  const sessionRecord = () => {
    if (!e.auth) return null;
    const sessionId = String(e.request.header.get("X-WesiOS-Session") || "").trim();
    if (!/^[A-Za-z0-9_-]{24,96}$/.test(sessionId)) return null;
    let record = null;
    try {
      record = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='__wesios_security__' && coll='security' && rid='session:" + sessionId + "' && deleted=false",
      );
    } catch (_) {
      return null;
    }
    let payload = {};
    try {
      const model = new DynamicModel({"userId": "", "revokedAt": "", "expiresAt": ""});
      record.unmarshalJSONField("payload", model);
      payload = {
        "userId": String(model.userId || ""),
        "revokedAt": String(model.revokedAt || ""),
        "expiresAt": String(model.expiresAt || ""),
      };
    } catch (_) {
      payload = {};
    }
    if (String(payload.userId || "") !== e.auth.id) return null;
    if (payload.revokedAt) return null;
    const expiresAt = Date.parse(String(payload.expiresAt || ""));
    if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) return null;
    return {"record": record, "payload": payload, "id": sessionId};
  };

  // No client may obtain a usable password-auth token directly. The only
  // supported password flow is /api/wesi/auth/start -> email code -> verify.
  if (method === "POST" && path === "/api/collections/users/auth-with-password") {
    throw new ForbiddenError("Используйте защищённый вход WesiOS с кодом из почты");
  }

  // Old owner builds must not be able to create/update a profile without a
  // real security email after this server hook is deployed.
  if (method === "POST" &&
      (path === "/api/wesi/portal/employees/provision" ||
       path === "/api/wesi/portal/employees/access" ||
       path === "/api/wesi/portal/profile/credentials")) {
    const requestBody = body();
    if (!validEmail(requestBody.email)) {
      throw new BadRequestError("Укажите действующую электронную почту для кодов безопасности");
    }
  }

  const needsSession =
    path === "/api/collections/users/auth-refresh" ||
    path.startsWith("/api/collections/wesios_records/records") ||
    path === "/api/wesi/app/bootstrap" ||
    path === "/api/wesi/portal/session" ||
    path === "/api/wesi/portal/manifest" ||
    path === "/api/wesi/portal/profile/credentials" ||
    path.startsWith("/api/wesi/portal/download/") ||
    path.startsWith("/api/wesi/portal/employees/") ||
    path.startsWith("/api/wesi/security/");

  if (needsSession && e.auth && !e.hasSuperuserAuth()) {
    const current = sessionRecord();
    if (!current) {
      throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
    }
    e.set("wesiSessionId", current.id);
  }

  return e.next();
});

/// Step 1. Validate login/password, locate the employee's real email and send
/// a one-time six-digit code. No auth token is issued at this stage.
routerAdd("POST", "/api/wesi/auth/start", (e) => {
  const normalizeLogin = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
      throw new BadRequestError("Неверный логин или пароль");
    }
    return normalized;
  };
  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({
        "kind": "", "userId": "", "email": "", "fullName": "", "name": "",
        "id": "", "login": "", "usedAt": "", "sentAt": "",
      });
      record.unmarshalJSONField(field, model);
      return {
        "kind": String(model.kind || ""), "userId": String(model.userId || ""),
        "email": String(model.email || ""), "fullName": String(model.fullName || ""),
        "name": String(model.name || ""), "id": String(model.id || ""),
        "login": String(model.login || ""), "usedAt": String(model.usedAt || ""),
        "sentAt": String(model.sentAt || ""),
      };
    } catch (_) { return {}; }
  };
  const realEmail = (value) => {
    const email = String(value || "").trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith("@wesi.local")
      ? email
      : "";
  };
  const maskEmail = (email) => {
    const parts = email.split("@");
    if (parts.length !== 2) return "***";
    const local = parts[0];
    const shown = local.length <= 2
      ? local.substring(0, 1) + "*"
      : local.substring(0, 2) + "***" + local.substring(local.length - 1);
    return shown + "@" + parts[1];
  };
  const ownerMarker = (userId) => {
    try {
      return e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='" + userId + "' && coll='system' && rid='portal-owner' && deleted=false",
      );
    } catch (_) { return null; }
  };

  const request = e.requestInfo().body || {};
  const login = normalizeLogin(request.login);
  const password = String(request.password || "");
  const purpose = request.purpose === "portal" ? "portal" : "app";
  if (!password) throw new BadRequestError("Неверный логин или пароль");

  let user = null;
  try {
    user = e.app.findAuthRecordByEmail("users", login + "@wesi.local");
  } catch (_) {
    user = null;
  }
  if (!user || !user.validatePassword(password)) {
    throw new UnauthorizedError("Неверный логин или пароль");
  }

  let employeeId = "";
  let email = "";
  let displayName = user.getString("name") || login;

  const owner = ownerMarker(user.id);
  if (owner) {
    employeeId = "owner";
    const ownerPayload = valueObject(owner, "payload");
    email = realEmail(ownerPayload.email);
    try {
      const employeeRecord = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='" + user.id + "' && coll='employees' && rid='owner' && deleted=false",
      );
      const payload = valueObject(employeeRecord, "payload");
      email = email || realEmail(payload.email);
      displayName = String(payload.fullName || payload.name || displayName);
    } catch (_) {}
  } else {
    let link = null;
    try {
      link = e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid='portal-account:" + user.id + "' && deleted=false",
      );
    } catch (_) {
      link = null;
    }
    if (!link) {
      throw new ForbiddenError("Профиль сотрудника закрыт или не активирован");
    }
    const payload = valueObject(link, "payload");
    employeeId = String(payload.employeeId || "");
    email = realEmail(payload.email);
    displayName = String(payload.fullName || payload.name || displayName);
    if (!employeeId) {
      throw new ForbiddenError("Профиль сотрудника не активирован");
    }
  }

  if (!email) {
    throw new ForbiddenError(
      "Для профиля не указана действующая электронная почта. Владелец должен добавить её в карточку сотрудника",
    );
  }

  // Prevent rapid resend abuse for this account.
  let securityRecords = [];
  try {
    securityRecords = e.app.findRecordsByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && deleted=false",
      "-stamp",
      300,
      0,
    );
  } catch (_) {
    securityRecords = [];
  }
  for (const item of securityRecords) {
    const payload = valueObject(item, "payload");
    if (payload.kind !== "otp" || String(payload.userId || "") !== user.id || payload.usedAt) continue;
    const sentAt = Date.parse(String(payload.sentAt || ""));
    if (Number.isFinite(sentAt) && Date.now() - sentAt < 30000) {
      throw new TooManyRequestsError("Новый код можно запросить через несколько секунд");
    }
  }

  const challengeId = $security.randomStringWithAlphabet(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
  const salt = $security.randomStringWithAlphabet(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
  const code = $security.randomStringWithAlphabet(6, "0123456789");
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 10 * 60 * 1000);
  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const challenge = new Record(collection);
  challenge.set("owner", "__wesios_security__");
  challenge.set("org", "wesi-inc");
  challenge.set("coll", "security");
  challenge.set("rid", "otp:" + challengeId);
  challenge.set("payload", {
    "kind": "otp",
    "challengeId": challengeId,
    "userId": user.id,
    "employeeId": employeeId,
    "login": login,
    "email": email,
    "purpose": purpose,
    "hash": $security.sha256(challengeId + ":" + salt + ":" + code),
    "salt": salt,
    "attempts": 0,
    "sentAt": now.toISOString(),
    "expiresAt": expiresAt.toISOString(),
  });
  challenge.set("stamp", now.toISOString());
  challenge.set("deleted", false);
  e.app.save(challenge);

  const subject = purpose === "portal"
    ? "Код входа на портал WesiOS"
    : "Код входа в WesiOS";
  const message = new MailerMessage({
    "from": {
      "address": e.app.settings().meta.senderAddress,
      "name": e.app.settings().meta.senderName || "WesiOS",
    },
    "to": [{"address": email, "name": displayName}],
    "subject": subject,
    "html": "<div style=\"font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px\">" +
      "<h2 style=\"margin:0 0 16px\">WesiOS</h2>" +
      "<p>Код подтверждения входа:</p>" +
      "<div style=\"font-size:34px;font-weight:700;letter-spacing:8px;margin:22px 0\">" + code + "</div>" +
      "<p>Код действует 10 минут. Если вход выполняете не вы — никому не сообщайте этот код.</p>" +
      "</div>",
    "text": "Код подтверждения WesiOS: " + code + ". Код действует 10 минут.",
  });
  try {
    e.app.newMailClient().send(message);
  } catch (error) {
    challenge.set("deleted", true);
    challenge.set("stamp", new Date().toISOString());
    e.app.save(challenge);
    console.log("WesiOS security email delivery failed:", error);
    throw new InternalServerError("Не удалось отправить код на почту. Повторите позже");
  }

  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": maskEmail(email),
    "expiresInSeconds": 600,
  });
});

/// Step 2. Validate the email code and only then issue a PocketBase token and
/// a revocable WesiOS session id.
routerAdd("POST", "/api/wesi/auth/verify", (e) => {
  const valueObject = (record, field) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({
        "kind": "", "challengeId": "", "userId": "", "employeeId": "",
        "login": "", "email": "", "purpose": "", "hash": "", "salt": "",
        "attempts": 0, "sentAt": "", "expiresAt": "", "usedAt": "",
      });
      record.unmarshalJSONField(field, model);
      return {
        "kind": String(model.kind || ""), "challengeId": String(model.challengeId || ""),
        "userId": String(model.userId || ""), "employeeId": String(model.employeeId || ""),
        "login": String(model.login || ""), "email": String(model.email || ""),
        "purpose": String(model.purpose || ""), "hash": String(model.hash || ""),
        "salt": String(model.salt || ""), "attempts": Number(model.attempts || 0),
        "sentAt": String(model.sentAt || ""), "expiresAt": String(model.expiresAt || ""),
        "usedAt": String(model.usedAt || ""),
      };
    } catch (_) { return {}; }
  };
  const request = e.requestInfo().body || {};
  const challengeId = String(request.challengeId || "").trim();
  const code = String(request.code || "").trim();
  const remember = request.remember === true;
  if (!/^[A-Za-z0-9]{40}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
    throw new BadRequestError("Введите шестизначный код");
  }

  let challenge = null;
  try {
    challenge = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='otp:" + challengeId + "' && deleted=false",
    );
  } catch (_) {
    challenge = null;
  }
  if (!challenge) throw new UnauthorizedError("Код недействителен или уже использован");

  const payload = valueObject(challenge, "payload");
  const expiresAt = Date.parse(String(payload.expiresAt || ""));
  if (payload.usedAt || !Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    challenge.set("deleted", true);
    challenge.set("stamp", new Date().toISOString());
    e.app.save(challenge);
    throw new UnauthorizedError("Срок действия кода истёк. Запросите новый");
  }

  const attempts = Number(payload.attempts || 0);
  if (attempts >= 5) {
    challenge.set("deleted", true);
    challenge.set("stamp", new Date().toISOString());
    e.app.save(challenge);
    throw new UnauthorizedError("Слишком много неверных попыток. Запросите новый код");
  }

  const expected = String(payload.hash || "");
  const actual = $security.sha256(challengeId + ":" + String(payload.salt || "") + ":" + code);
  if (!expected || expected !== actual) {
    payload.attempts = attempts + 1;
    challenge.set("payload", payload);
    challenge.set("stamp", new Date().toISOString());
    if (payload.attempts >= 5) challenge.set("deleted", true);
    e.app.save(challenge);
    throw new UnauthorizedError(
      payload.attempts >= 5
        ? "Слишком много неверных попыток. Запросите новый код"
        : "Неверный код",
    );
  }

  const userId = String(payload.userId || "");
  let user = null;
  try { user = e.app.findRecordById("users", userId); } catch (_) { user = null; }
  if (!user) throw new ForbiddenError("Профиль закрыт");

  // The employee link must still exist at the exact moment the code is used.
  if (String(payload.employeeId || "") !== "owner") {
    try {
      e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid='portal-account:" + user.id + "' && deleted=false",
      );
    } catch (_) {
      throw new ForbiddenError("Профиль сотрудника закрыт");
    }
  }

  payload.usedAt = new Date().toISOString();
  challenge.set("payload", payload);
  challenge.set("deleted", true);
  challenge.set("stamp", payload.usedAt);
  e.app.save(challenge);

  const sessionId = $security.randomStringWithAlphabet(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-");
  const durationSeconds = remember ? 315360000 : 43200; // revocable server session
  const expires = new Date(Date.now() + durationSeconds * 1000);
  const meta = request.device && typeof request.device === "object" ? request.device : {};
  const platform = String(meta.platform || "").substring(0, 80);
  const deviceName = String(meta.deviceName || "").substring(0, 160);
  const timezone = String(meta.timezone || "").substring(0, 80);
  const country = String(meta.country || "").substring(0, 80);
  const userAgent = String(e.request.header.get("User-Agent") || meta.userAgent || "").substring(0, 360);

  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const session = new Record(collection);
  session.set("owner", "__wesios_security__");
  session.set("org", "wesi-inc");
  session.set("coll", "security");
  session.set("rid", "session:" + sessionId);
  session.set("payload", {
    "kind": "session",
    "sessionId": sessionId,
    "userId": user.id,
    "employeeId": String(payload.employeeId || ""),
    "login": String(payload.login || ""),
    "email": String(payload.email || ""),
    "purpose": String(payload.purpose || "app"),
    "remember": remember,
    "createdAt": new Date().toISOString(),
    "lastSeenAt": new Date().toISOString(),
    "expiresAt": expires.toISOString(),
    "ip": e.realIP(),
    "platform": platform,
    "deviceName": deviceName,
    "timezone": timezone,
    "country": country,
    "userAgent": userAgent,
  });
  session.set("stamp", new Date().toISOString());
  session.set("deleted", false);
  e.app.save(session);

  return e.json(200, {
    "token": user.newStaticAuthToken(durationSeconds),
    "userId": user.id,
    "sessionId": sessionId,
    "expiresAt": expires.toISOString(),
    "record": {
      "id": user.id,
      "name": user.getString("name"),
      "email": String(payload.email || ""),
      "login": String(payload.login || ""),
    },
  });
});

routerAdd("GET", "/api/wesi/security/session/ping", (e) => {
  const sessionId = String(e.get("wesiSessionId") || "");
  if (!sessionId) throw new UnauthorizedError("Сеанс завершён");
  let record = null;
  try {
    record = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='session:" + sessionId + "' && deleted=false",
    );
  } catch (_) { record = null; }
  if (!record) throw new UnauthorizedError("Сеанс завершён");
  let payload = {};
  try {
    const model = new DynamicModel({
      "kind": "", "sessionId": "", "userId": "", "employeeId": "",
      "login": "", "email": "", "purpose": "", "remember": false,
      "createdAt": "", "lastSeenAt": "", "expiresAt": "", "ip": "",
      "platform": "", "deviceName": "", "timezone": "", "country": "",
      "userAgent": "", "revokedAt": "", "revokedReason": "",
    });
    record.unmarshalJSONField("payload", model);
    payload = {
      "kind": String(model.kind || ""), "sessionId": String(model.sessionId || ""),
      "userId": String(model.userId || ""), "employeeId": String(model.employeeId || ""),
      "login": String(model.login || ""), "email": String(model.email || ""),
      "purpose": String(model.purpose || ""), "remember": model.remember === true,
      "createdAt": String(model.createdAt || ""), "lastSeenAt": String(model.lastSeenAt || ""),
      "expiresAt": String(model.expiresAt || ""), "ip": String(model.ip || ""),
      "platform": String(model.platform || ""), "deviceName": String(model.deviceName || ""),
      "timezone": String(model.timezone || ""), "country": String(model.country || ""),
      "userAgent": String(model.userAgent || ""), "revokedAt": String(model.revokedAt || ""),
      "revokedReason": String(model.revokedReason || ""),
    };
  } catch (_) {}
  const lastSeen = Date.parse(String(payload.lastSeenAt || ""));
  if (!Number.isFinite(lastSeen) || Date.now() - lastSeen > 30000) {
    payload.lastSeenAt = new Date().toISOString();
    payload.ip = e.realIP();
    record.set("payload", payload);
    record.set("stamp", payload.lastSeenAt);
    e.app.save(record);
  }
  return e.json(200, {"ok": true, "sessionId": sessionId});
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/security/sessions", (e) => {
  const valueObject = (record) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({
        "kind": "", "sessionId": "", "userId": "", "employeeId": "",
        "purpose": "", "createdAt": "", "lastSeenAt": "", "expiresAt": "",
        "remember": false, "ip": "", "platform": "", "deviceName": "",
        "timezone": "", "country": "", "userAgent": "", "revokedAt": "",
      });
      record.unmarshalJSONField("payload", model);
      return {
        "kind": String(model.kind || ""), "sessionId": String(model.sessionId || ""),
        "userId": String(model.userId || ""), "employeeId": String(model.employeeId || ""),
        "purpose": String(model.purpose || ""), "createdAt": String(model.createdAt || ""),
        "lastSeenAt": String(model.lastSeenAt || ""), "expiresAt": String(model.expiresAt || ""),
        "remember": model.remember === true, "ip": String(model.ip || ""),
        "platform": String(model.platform || ""), "deviceName": String(model.deviceName || ""),
        "timezone": String(model.timezone || ""), "country": String(model.country || ""),
        "userAgent": String(model.userAgent || ""), "revokedAt": String(model.revokedAt || ""),
      };
    } catch (_) { return {}; }
  };
  const currentId = String(e.get("wesiSessionId") || "");
  let records = [];
  try {
    records = e.app.findRecordsByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && deleted=false",
      "-stamp",
      1000,
      0,
    );
  } catch (_) { records = []; }

  const items = [];
  for (const record of records) {
    const payload = valueObject(record);
    if (payload.kind !== "session" || String(payload.userId || "") !== e.auth.id || payload.revokedAt) continue;
    const expiresAt = Date.parse(String(payload.expiresAt || ""));
    if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) continue;
    items.push({
      "id": String(payload.sessionId || ""),
      "current": String(payload.sessionId || "") === currentId,
      "purpose": String(payload.purpose || "app"),
      "createdAt": String(payload.createdAt || ""),
      "lastSeenAt": String(payload.lastSeenAt || payload.createdAt || ""),
      "expiresAt": String(payload.expiresAt || ""),
      "remember": payload.remember === true,
      "ip": String(payload.ip || ""),
      "platform": String(payload.platform || ""),
      "deviceName": String(payload.deviceName || ""),
      "timezone": String(payload.timezone || ""),
      "country": String(payload.country || ""),
      "userAgent": String(payload.userAgent || ""),
    });
  }
  return e.json(200, {"items": items});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/security/sessions/revoke", (e) => {
  const request = e.requestInfo().body || {};
  const targetId = String(request.sessionId || "").trim();
  if (!/^[A-Za-z0-9_-]{24,96}$/.test(targetId)) {
    throw new BadRequestError("Некорректный сеанс");
  }
  let target = null;
  try {
    target = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='session:" + targetId + "' && deleted=false",
    );
  } catch (_) { target = null; }
  if (!target) return e.json(200, {"ok": true, "alreadyEnded": true});
  let payload = {};
  try {
    const model = new DynamicModel({
      "kind": "", "sessionId": "", "userId": "", "employeeId": "",
      "login": "", "email": "", "purpose": "", "remember": false,
      "createdAt": "", "lastSeenAt": "", "expiresAt": "", "ip": "",
      "platform": "", "deviceName": "", "timezone": "", "country": "",
      "userAgent": "", "revokedAt": "", "revokedReason": "",
    });
    target.unmarshalJSONField("payload", model);
    payload = {
      "kind": String(model.kind || ""), "sessionId": String(model.sessionId || ""),
      "userId": String(model.userId || ""), "employeeId": String(model.employeeId || ""),
      "login": String(model.login || ""), "email": String(model.email || ""),
      "purpose": String(model.purpose || ""), "remember": model.remember === true,
      "createdAt": String(model.createdAt || ""), "lastSeenAt": String(model.lastSeenAt || ""),
      "expiresAt": String(model.expiresAt || ""), "ip": String(model.ip || ""),
      "platform": String(model.platform || ""), "deviceName": String(model.deviceName || ""),
      "timezone": String(model.timezone || ""), "country": String(model.country || ""),
      "userAgent": String(model.userAgent || ""), "revokedAt": String(model.revokedAt || ""),
      "revokedReason": String(model.revokedReason || ""),
    };
  } catch (_) {}
  if (String(payload.userId || "") !== e.auth.id) {
    throw new ForbiddenError("Нельзя завершить чужой сеанс");
  }
  payload.revokedAt = new Date().toISOString();
  payload.revokedReason = targetId === String(e.get("wesiSessionId") || "")
    ? "logout"
    : "remote";
  target.set("payload", payload);
  target.set("deleted", true);
  target.set("stamp", payload.revokedAt);
  e.app.save(target);
  return e.json(200, {"ok": true, "current": targetId === String(e.get("wesiSessionId") || "")});
}, $apis.requireAuth("users"));

/// Removing an auth record invalidates every device immediately at the WesiOS
/// session layer as well. This also cleans pending OTP challenges.
onRecordAfterDeleteSuccess((e) => {
  const deletedUserId = e.record.id;
  let records = [];
  try {
    records = e.app.findRecordsByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && deleted=false",
      "-stamp",
      2000,
      0,
    );
  } catch (_) { records = []; }
  for (const record of records) {
    let payload = {};
    try {
      const model = new DynamicModel({
        "kind": "", "sessionId": "", "userId": "", "employeeId": "",
        "login": "", "email": "", "purpose": "", "remember": false,
        "createdAt": "", "lastSeenAt": "", "expiresAt": "", "ip": "",
        "platform": "", "deviceName": "", "timezone": "", "country": "",
        "userAgent": "", "revokedAt": "", "revokedReason": "",
      });
      record.unmarshalJSONField("payload", model);
      payload = {
        "kind": String(model.kind || ""), "sessionId": String(model.sessionId || ""),
        "userId": String(model.userId || ""), "employeeId": String(model.employeeId || ""),
        "login": String(model.login || ""), "email": String(model.email || ""),
        "purpose": String(model.purpose || ""), "remember": model.remember === true,
        "createdAt": String(model.createdAt || ""), "lastSeenAt": String(model.lastSeenAt || ""),
        "expiresAt": String(model.expiresAt || ""), "ip": String(model.ip || ""),
        "platform": String(model.platform || ""), "deviceName": String(model.deviceName || ""),
        "timezone": String(model.timezone || ""), "country": String(model.country || ""),
        "userAgent": String(model.userAgent || ""), "revokedAt": String(model.revokedAt || ""),
        "revokedReason": String(model.revokedReason || ""),
      };
    } catch (_) {}
    if (String(payload.userId || "") !== deletedUserId) continue;
    payload.revokedAt = new Date().toISOString();
    payload.revokedReason = "profile-deleted";
    record.set("payload", payload);
    record.set("deleted", true);
    record.set("stamp", payload.revokedAt);
    try { e.app.save(record); } catch (_) {}
  }
  e.next();
}, "users");
