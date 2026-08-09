routerAdd("GET", "/api/wesi/auth/version", (e) => {
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
    "version": "2026-08-09.owner-email-v4",
    "jsonReadable": jsonReadable,
  });
});

/// Safe migration for the owner account when an old installation has no real
/// security email yet. Password validation creates only a short-lived setup
/// challenge. The email is not committed until a code sent to that address
/// has been verified and a real WesiOS session exists.

const wesiReadMailConfig = () => {
  try {
    const raw = $os.readFile(__hooks + "/.wesi-mail.json");
    const text = typeof raw === "string"
      ? raw
      : String.fromCharCode.apply(null, raw || []);
    const parsed = JSON.parse(text || "{}");
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (_) {
    return {};
  }
};

const wesiDeliverMail = (app, email, displayName, subject, html, text) => {
  const settings = app.settings();
  const smtpReady = Boolean(
    settings && settings.smtp && settings.smtp.enabled === true &&
    String(settings.smtp.host || "").trim(),
  );

  if (smtpReady) {
    const message = new MailerMessage({
      "from": {
        "address": settings.meta.senderAddress,
        "name": settings.meta.senderName || "WesiOS",
      },
      "to": [{"address": email, "name": displayName}],
      "subject": subject,
      "html": html,
      "text": text,
    });
    try {
      app.newMailClient().send(message);
      return "smtp";
    } catch (error) {
      console.log("WesiOS SMTP delivery failed, trying HTTPS provider:", error);
    }
  }

  const config = wesiReadMailConfig();
  const provider = String(config.provider || "").trim().toLowerCase();
  const apiKey = String(config.apiKey || "").trim();
  const from = String(config.from || "").trim();
  if (provider !== "resend" || !apiKey || !from) {
    throw new Error("No working WesiOS mail transport configured");
  }

  const response = $http.send({
    "url": "https://api.resend.com/emails",
    "method": "POST",
    "headers": {
      "Authorization": "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    "body": JSON.stringify({
      "from": from,
      "to": [email],
      "subject": subject,
      "html": html,
      "text": text,
    }),
    "timeout": 20,
  });
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw new Error("HTTPS mail provider returned HTTP " + response.statusCode);
  }
  return "https";
};

routerAdd("POST", "/api/wesi/auth/start-v2", (e) => {
  const valueObject = (record) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({"email": "", "fullName": "", "name": ""});
      record.unmarshalJSONField("payload", model);
      return {
        "email": String(model.email || ""),
        "fullName": String(model.fullName || ""),
        "name": String(model.name || ""),
      };
    } catch (_) {}
    try {
      const raw = record.get("payload");
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };
  const validEmail = (value) => {
    const email = String(value || "").trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith("@wesi.local") ? email : "";
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
  const sendCode = (email, displayName, purpose, challengeId, challenge, payload) => {
    const code = $security.randomStringWithAlphabet(6, "0123456789");
    const salt = $security.randomStringWithAlphabet(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    payload.kind = "otp";
    payload.email = email;
    payload.hash = $security.sha256(challengeId + ":" + salt + ":" + code);
    payload.salt = salt;
    payload.attempts = 0;
    payload.sentAt = new Date().toISOString();
    payload.expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    challenge.set("payload", payload);
    challenge.set("stamp", payload.sentAt);
    e.app.save(challenge);

    const subject = purpose === "portal" ? "Код входа на портал WesiOS" : "Код входа в WesiOS";
    const html = "<div style=\"font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px\">" +
      "<h2>WesiOS</h2><p>Код подтверждения входа:</p>" +
      "<div style=\"font-size:34px;font-weight:700;letter-spacing:8px;margin:22px 0\">" + code + "</div>" +
      "<p>Код действует 10 минут. Если вход выполняете не вы — никому не сообщайте этот код.</p></div>";
    const text = "Код подтверждения WesiOS: " + code + ". Код действует 10 минут.";
    try {
      payload.delivery = wesiDeliverMail(e.app, email, displayName, subject, html, text);
      challenge.set("payload", payload);
      e.app.save(challenge);
    } catch (error) {
      challenge.set("deleted", true);
      challenge.set("stamp", new Date().toISOString());
      e.app.save(challenge);
      console.log("WesiOS security email delivery failed:", error);
      throw new InternalServerError("Не удалось отправить код на почту. Повторите позже");
    }
  };

  const body = e.requestInfo().body || {};
  const login = String(body.login || "").trim().toLowerCase();
  const password = String(body.password || "");
  const purpose = body.purpose === "portal" ? "portal" : "app";
  if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(login) || !password) {
    throw new UnauthorizedError("Неверный логин или пароль");
  }

  let user = null;
  try { user = e.app.findAuthRecordByEmail("users", login + "@wesi.local"); } catch (_) { user = null; }
  if (!user || !user.validatePassword(password)) {
    throw new UnauthorizedError("Неверный логин или пароль");
  }

  let owner = null;
  try {
    owner = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + user.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) { owner = null; }

  let employeeId = "";
  let email = "";
  let displayName = user.getString("name") || login;
  if (owner) {
    employeeId = "owner";
    const ownerPayload = valueObject(owner);
    email = validEmail(ownerPayload.email);
    try {
      const employeeRecord = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='" + user.id + "' && coll='employees' && rid='owner' && deleted=false",
      );
      const p = valueObject(employeeRecord);
      email = email || validEmail(p.email);
      displayName = String(p.fullName || p.name || displayName);
    } catch (_) {}
  } else {
    let link = null;
    try {
      link = e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid='portal-account:" + user.id + "' && deleted=false",
      );
    } catch (_) { link = null; }
    if (!link) throw new ForbiddenError("Профиль сотрудника закрыт или не активирован");
    const p = valueObject(link);
    employeeId = String(p.employeeId || "");
    email = validEmail(p.email);
    displayName = String(p.fullName || p.name || displayName);
    if (!employeeId) throw new ForbiddenError("Профиль сотрудника не активирован");
    if (!email) {
      throw new ForbiddenError("Владелец должен добавить действующую электронную почту в карточку сотрудника");
    }
  }

  const challengeId = $security.randomStringWithAlphabet(40, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const challenge = new Record(collection);
  challenge.set("owner", "__wesios_security__");
  challenge.set("org", "wesi-inc");
  challenge.set("coll", "security");
  challenge.set("rid", "otp:" + challengeId);
  const payload = {
    "kind": email ? "otp" : "email-setup",
    "challengeId": challengeId,
    "userId": user.id,
    "employeeId": employeeId,
    "login": login,
    "email": email,
    "purpose": purpose,
    "ownerEmailSetup": !email && employeeId === "owner",
    "createdAt": new Date().toISOString(),
    "expiresAt": new Date(Date.now() + 10 * 60 * 1000).toISOString(),
  };
  challenge.set("payload", payload);
  challenge.set("stamp", payload.createdAt);
  challenge.set("deleted", false);
  e.app.save(challenge);

  if (!email && employeeId === "owner") {
    return e.json(200, {
      "challengeId": challengeId,
      "emailSetupRequired": true,
      "expiresInSeconds": 600,
    });
  }

  sendCode(email, displayName, purpose, challengeId, challenge, payload);
  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": maskEmail(email),
    "emailSetupRequired": false,
    "expiresInSeconds": 600,
  });
});

routerAdd("POST", "/api/wesi/auth/setup-email", (e) => {
  const valueObject = (record) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({
        "kind": "", "challengeId": "", "userId": "", "employeeId": "",
        "login": "", "email": "", "purpose": "", "ownerEmailSetup": false,
        "createdAt": "", "expiresAt": "", "hash": "", "salt": "",
        "attempts": 0, "sentAt": "", "delivery": "", "usedAt": "",
      });
      record.unmarshalJSONField("payload", model);
      return {
        "kind": String(model.kind || ""),
        "challengeId": String(model.challengeId || ""),
        "userId": String(model.userId || ""),
        "employeeId": String(model.employeeId || ""),
        "login": String(model.login || ""),
        "email": String(model.email || ""),
        "purpose": String(model.purpose || ""),
        "ownerEmailSetup": model.ownerEmailSetup === true,
        "createdAt": String(model.createdAt || ""),
        "expiresAt": String(model.expiresAt || ""),
        "hash": String(model.hash || ""),
        "salt": String(model.salt || ""),
        "attempts": Number(model.attempts || 0),
        "sentAt": String(model.sentAt || ""),
        "delivery": String(model.delivery || ""),
        "usedAt": String(model.usedAt || ""),
      };
    } catch (_) {}
    try {
      const raw = record.get("payload");
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };
  const validEmail = (value) => {
    const email = String(value || "").trim().toLowerCase();
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith("@wesi.local") ? email : "";
  };
  const maskEmail = (email) => {
    const parts = email.split("@");
    const local = parts[0] || "";
    const shown = local.length <= 2 ? local.substring(0, 1) + "*" : local.substring(0, 2) + "***" + local.substring(local.length - 1);
    return shown + "@" + (parts[1] || "");
  };
  const body = e.requestInfo().body || {};
  const challengeId = String(body.challengeId || "").trim();
  const email = validEmail(body.email);
  if (!/^[A-Za-z0-9]{40}$/.test(challengeId) || !email) {
    throw new BadRequestError("Укажите действующую электронную почту");
  }

  let challenge = null;
  try {
    challenge = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='otp:" + challengeId + "' && deleted=false",
    );
  } catch (_) { challenge = null; }
  if (!challenge) throw new UnauthorizedError("Проверка входа истекла");
  const payload = valueObject(challenge);
  if (payload.kind !== "email-setup" || String(payload.employeeId || "") !== "owner") {
    throw new ForbiddenError("Проверка привязки не соответствует профилю владельца [owner-email-v3]");
  }
  let ownerMarker = null;
  try {
    ownerMarker = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + String(payload.userId || "") + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) { ownerMarker = null; }
  if (!ownerMarker) {
    throw new ForbiddenError("Профиль владельца не закреплён [owner-email-v3]");
  }
  const expires = Date.parse(String(payload.expiresAt || ""));
  if (!Number.isFinite(expires) || expires <= Date.now()) {
    challenge.set("deleted", true);
    e.app.save(challenge);
    throw new UnauthorizedError("Проверка входа истекла. Начните заново");
  }

  const code = $security.randomStringWithAlphabet(6, "0123456789");
  const salt = $security.randomStringWithAlphabet(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
  payload.kind = "otp";
  payload.email = email;
  payload.hash = $security.sha256(challengeId + ":" + salt + ":" + code);
  payload.salt = salt;
  payload.attempts = 0;
  payload.sentAt = new Date().toISOString();
  payload.expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  challenge.set("payload", payload);
  challenge.set("stamp", payload.sentAt);
  e.app.save(challenge);

  let user = null;
  try { user = e.app.findRecordById("users", String(payload.userId || "")); } catch (_) { user = null; }
  if (!user) throw new ForbiddenError("Профиль владельца закрыт");

  const subject = "Подтверждение почты WesiOS";
  const html = "<div style=\"font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px\"><h2>WesiOS</h2><p>Код подтверждения почты и входа:</p><div style=\"font-size:34px;font-weight:700;letter-spacing:8px;margin:22px 0\">" + code + "</div><p>Код действует 10 минут.</p></div>";
  const text = "Код подтверждения WesiOS: " + code + ". Код действует 10 минут.";
  try {
    payload.delivery = wesiDeliverMail(
      e.app,
      email,
      user.getString("name") || String(payload.login || "WesiOS"),
      subject,
      html,
      text,
    );
    challenge.set("payload", payload);
    e.app.save(challenge);
  } catch (error) {
    console.log("WesiOS owner email setup delivery failed:", error);
    throw new InternalServerError("Не удалось отправить код на эту почту");
  }

  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": maskEmail(email),
    "authVersion": "2026-08-09.owner-email-v4",
    "expiresInSeconds": 600,
  });
});

/// Called only after /verify has issued a session for a challenge whose code
/// was delivered to the new owner email. The session payload therefore acts
/// as proof that this address was actually verified.
routerAdd("POST", "/api/wesi/security/confirm-owner-email", (e) => {
  const sid = String(e.get("wesiSessionId") || "");
  if (!sid) throw new UnauthorizedError("Нет подтверждённого сеанса");
  let session = null;
  try {
    session = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='session:" + sid + "' && deleted=false",
    );
  } catch (_) { session = null; }
  if (!session) throw new UnauthorizedError("Сеанс завершён");
  let sessionPayload = {};
  try {
    const model = new DynamicModel({"employeeId": "", "email": ""});
    session.unmarshalJSONField("payload", model);
    sessionPayload = {
      "employeeId": String(model.employeeId || ""),
      "email": String(model.email || ""),
    };
  } catch (_) {}
  if (String(sessionPayload.employeeId || "") !== "owner") {
    throw new ForbiddenError("Это не профиль владельца");
  }
  const email = String(sessionPayload.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.endsWith("@wesi.local")) {
    throw new BadRequestError("В сеансе нет подтверждённой почты");
  }

  let marker = null;
  try {
    marker = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + e.auth.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) { marker = null; }
  if (!marker) throw new ForbiddenError("Профиль владельца не закреплён");
  let payload = {};
  try {
    const model = new DynamicModel({
      "kind": "", "ownerId": "", "email": "",
      "emailVerifiedAt": "", "emailUpdatedAt": "",
    });
    marker.unmarshalJSONField("payload", model);
    payload = {
      "kind": String(model.kind || "portal-owner"),
      "ownerId": String(model.ownerId || e.auth.id),
      "email": String(model.email || ""),
      "emailVerifiedAt": String(model.emailVerifiedAt || ""),
      "emailUpdatedAt": String(model.emailUpdatedAt || ""),
    };
  } catch (_) {
    payload = {"kind": "portal-owner", "ownerId": e.auth.id};
  }
  payload.email = email;
  payload.emailVerifiedAt = new Date().toISOString();
  marker.set("payload", payload);
  marker.set("stamp", new Date().toISOString());
  e.app.save(marker);
  return e.json(200, {"ok": true, "email": email});
}, $apis.requireAuth("users"));