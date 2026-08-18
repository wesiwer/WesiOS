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
    "version": "2026-08-09.security-mail-v9",
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
      record = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:p_rid} && deleted=false", {"p_rid": "session:" + sessionId});
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
  const WESI_SECURITY_MAIL_TEMPLATE_VERSION = "2026-08-09.mail-design-v2";
  const WESI_SECURITY_MAIL_LOGO_URL = "https://api.wesi-inc.ru/portal/app_icon.png";
  
  /// Kept locally in this hook so legacy /auth/start remains independent from
  /// the newer bootstrap hook while rendering the same branded email.
  const wesiSecurityBuildOtpMail = (code, purpose) => {
    const safeCode = String(code || "").replace(/[^0-9]/g, "");
    const portal = purpose === "portal";
    const title = "Подтверждение входа";
    const lead = portal
      ? "Введите этот код на портале WesiOS, чтобы продолжить вход."
      : "Введите этот код в приложении WesiOS, чтобы продолжить вход.";
    const textLead = portal ? "Код входа на портал WesiOS" : "Код входа в WesiOS";
  
    const html = "<!doctype html>" +
      "<html lang=\"ru\"><head><meta charset=\"utf-8\">" +
      "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
      "<meta name=\"color-scheme\" content=\"dark\">" +
      "<meta name=\"supported-color-schemes\" content=\"dark\">" +
      "<meta name=\"x-wesios-template\" content=\"" + WESI_SECURITY_MAIL_TEMPLATE_VERSION + "\">" +
      "<title>" + title + " · WesiOS</title>" +
      "<style>@media only screen and (max-width:620px){" +
      ".wesi-shell{padding:16px!important}.wesi-card{border-radius:20px!important}" +
      ".wesi-pad{padding-left:24px!important;padding-right:24px!important}" +
      ".wesi-code{font-size:36px!important;letter-spacing:7px!important}" +
      "}</style></head>" +
      "<body style=\"margin:0;padding:0;background:#09090B;color:#F7F7F8;\">" +
      "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;\">" +
      "Код подтверждения входа в WesiOS действует 10 минут.&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;</div>" +
      "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#09090B\" style=\"width:100%;background:#09090B;\">" +
      "<tr><td class=\"wesi-shell\" align=\"center\" style=\"padding:36px 16px;\">" +
      "<table role=\"presentation\" class=\"wesi-card\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#121216\" style=\"width:100%;max-width:560px;background:#121216;border:1px solid #29292F;border-radius:28px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.35);\">" +
      "<tr><td height=\"4\" bgcolor=\"#F97316\" style=\"height:4px;background:#F97316;font-size:0;line-height:0;\">&nbsp;</td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:30px 36px 16px;\">" +
      "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr>" +
      "<td width=\"64\" valign=\"middle\"><img src=\"" + WESI_SECURITY_MAIL_LOGO_URL + "\" width=\"56\" height=\"56\" alt=\"WesiOS\" style=\"display:block;width:56px;height:56px;border:0;border-radius:16px;\"></td>" +
      "<td valign=\"middle\" style=\"padding-left:14px;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
      "<div style=\"font-size:20px;line-height:24px;font-weight:700;letter-spacing:.2px;color:#FFFFFF;\">WesiOS</div>" +
      "<div style=\"margin-top:4px;font-size:11px;line-height:15px;font-weight:700;letter-spacing:1.5px;color:#84CC16;\">SECURITY CENTER</div>" +
      "</td></tr></table></td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:22px 36px 0;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
      "<div style=\"font-size:11px;line-height:16px;font-weight:700;letter-spacing:1.6px;color:#F97316;\">КОД БЕЗОПАСНОСТИ</div>" +
      "<h1 style=\"margin:10px 0 12px;font-size:30px;line-height:36px;font-weight:750;letter-spacing:-.5px;color:#FFFFFF;\">" + title + "</h1>" +
      "<p style=\"margin:0;font-size:16px;line-height:25px;color:#B8B8C2;\">" + lead + "</p>" +
      "</td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:26px 36px 0;\">" +
      "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#09090B\" style=\"width:100%;background:#09090B;border:1px solid #303038;border-radius:18px;\">" +
      "<tr><td align=\"center\" style=\"padding:14px 20px 4px;font-family:Arial,'Helvetica Neue',sans-serif;font-size:10px;line-height:14px;font-weight:700;letter-spacing:1.5px;color:#7F808B;\">ОДНОРАЗОВЫЙ КОД</td></tr>" +
      "<tr><td class=\"wesi-code\" align=\"center\" style=\"padding:4px 14px 18px;font-family:'Courier New',Courier,monospace;font-size:42px;line-height:50px;font-weight:700;letter-spacing:10px;color:#FFFFFF;font-variant-numeric:tabular-nums;\">" + safeCode + "</td></tr>" +
      "</table></td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:18px 36px 0;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
      "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr>" +
      "<td width=\"10\" valign=\"middle\"><span style=\"display:block;width:8px;height:8px;background:#84CC16;border-radius:99px;\"></span></td>" +
      "<td valign=\"middle\" style=\"padding-left:8px;font-size:13px;line-height:19px;color:#D2D2D8;\">Код действует <strong style=\"color:#FFFFFF;\">10 минут</strong> и подходит только для одной попытки входа.</td>" +
      "</tr></table></td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:24px 36px 32px;\">" +
      "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#1A1715\" style=\"width:100%;background:#1A1715;border-left:3px solid #F97316;border-radius:12px;\">" +
      "<tr><td style=\"padding:15px 16px;font-family:Arial,'Helvetica Neue',sans-serif;font-size:13px;line-height:20px;color:#C8C4C1;\"><strong style=\"color:#FFFFFF;\">Не запрашивали код?</strong><br>Ничего не вводите и никому его не сообщайте. Пароль WesiOS остаётся скрытым и в письме не передаётся.</td></tr>" +
      "</table></td></tr>" +
      "<tr><td class=\"wesi-pad\" style=\"padding:18px 36px 24px;border-top:1px solid #29292F;font-family:Arial,'Helvetica Neue',sans-serif;font-size:12px;line-height:19px;color:#777781;\">" +
      "Это автоматическое системное письмо. Отвечать на него не нужно.<br>" +
      "<span style=\"color:#A5A5AE;\">WesiOS · security@wesi-inc.ru</span>" +
      "</td></tr></table>" +
      "<div style=\"max-width:560px;padding:18px 12px 0;font-family:Arial,'Helvetica Neue',sans-serif;font-size:11px;line-height:17px;color:#5F6069;text-align:center;\">Защищённая авторизация WesiOS</div>" +
      "</td></tr></table></body></html>";
  
    const text = "WesiOS\n\n" + textLead + ": " + safeCode +
      "\n\nКод действует 10 минут и подходит только для одной попытки входа." +
      "\n\nЕсли вы не запрашивали код, ничего не вводите и никому его не сообщайте." +
      "\n\nЭто автоматическое системное письмо. Отвечать на него не нужно.";
  
    const asciiHtml = html.replace(/[^\x00-\x7F]/g, (character) =>
      "&#" + character.charCodeAt(0) + ";"
    );
    return {"html": asciiHtml, "text": text};
  };

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
        "kind": "", "userId": "", "employeeId": "", "email": "",
        "fullName": "", "name": "", "id": "", "login": "",
        "usedAt": "", "sentAt": "",
      });
      record.unmarshalJSONField(field, model);
      return {
        "kind": String(model.kind || ""), "userId": String(model.userId || ""),
        "employeeId": String(model.employeeId || ""),
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
      return e.app.findFirstRecordByFilter("wesios_records", "owner={:p_owner} && coll='system' && rid='portal-owner' && deleted=false", {"p_owner": userId});
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
      const employeeRecord = e.app.findFirstRecordByFilter("wesios_records", "owner={:p_owner} && coll='employees' && rid='owner' && deleted=false", {"p_owner": user.id});
      const payload = valueObject(employeeRecord, "payload");
      email = email || realEmail(payload.email);
      displayName = String(payload.fullName || payload.name || displayName);
    } catch (_) {}
  } else {
    let link = null;
    try {
      link = e.app.findFirstRecordByFilter("wesios_records", "coll='system' && rid={:p_rid} && deleted=false", {"p_rid": "portal-account:" + user.id});
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
  const mail = wesiSecurityBuildOtpMail(code, purpose);
  const message = new MailerMessage({
    "from": {
      "address": e.app.settings().meta.senderAddress,
      "name": e.app.settings().meta.senderName || "WesiOS",
    },
    "to": [{"address": email, "name": displayName}],
    "subject": subject,
    "html": mail.html,
    "text": mail.text,
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
    challenge = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:p_rid} && deleted=false", {"p_rid": "otp:" + challengeId});
  } catch (_) {
    challenge = null;
  }
  if (!challenge) {
    let previous = null;
    try {
      previous = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:p_rid}", {"p_rid": "otp:" + challengeId});
    } catch (_) {
      previous = null;
    }
    if (previous) {
      const previousPayload = valueObject(previous, "payload");
      if (previousPayload.usedAt) {
        throw new UnauthorizedError("Код уже использован. Запросите новый код");
      }
      throw new UnauthorizedError("Эта попытка входа завершена. Запросите новый код");
    }
    throw new UnauthorizedError("Проверка входа истекла. Запросите новый код");
  }

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
      e.app.findFirstRecordByFilter("wesios_records", "coll='system' && rid={:p_rid} && deleted=false", {"p_rid": "portal-account:" + user.id});
    } catch (_) {
      throw new ForbiddenError("Профиль сотрудника закрыт");
    }
  }

  const sessionId = $security.randomStringWithAlphabet(48, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-");
  const durationSeconds = remember ? 315360000 : 43200; // revocable server session
  // PocketBase expects Go time.Duration here (nanoseconds), not seconds.
  // Passing durationSeconds directly made the token expire in under a second.
  const authToken = user.newStaticAuthToken(durationSeconds * 1000000000);
  let authenticatedUser = null;
  try { authenticatedUser = e.app.findAuthRecordByToken(authToken, "auth"); } catch (_) {}
  if (!authenticatedUser || authenticatedUser.id !== user.id) {
    throw new InternalServerError("Не удалось выпустить подтверждённый сеанс");
  }
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

  // Consume the one-time code only after both token generation and persistent
  // session creation have succeeded. A server-side failure remains retryable.
  payload.usedAt = new Date().toISOString();
  challenge.set("payload", payload);
  challenge.set("deleted", true);
  challenge.set("stamp", payload.usedAt);
  e.app.save(challenge);

  return e.json(200, {
    "token": authToken,
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
    record = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:p_rid} && deleted=false", {"p_rid": "session:" + sessionId});
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
    target = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:p_rid} && deleted=false", {"p_rid": "session:" + targetId});
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

/// Заголовки безопасности на каждый ответ.
///
/// До этого сервер отдавал только `X-Content-Type-Options` и
/// `X-Frame-Options` — их ставит сам PocketBase. Не хватало двух вещей.
///
/// HSTS. Без него первый заход по http на `api.wesi-inc.ru` можно перехватить
/// и увести на подставной адрес: браузер узнаёт про https только из ответа,
/// который ещё не получил. Год и поддомены — обычная величина. `preload`
/// намеренно не ставится: это одностороннее решение, откатить его нельзя.
///
/// CSP. Единственное, что продолжает работать, если межсайтовый скрипт всё
/// же появится. Политика разная по назначению адреса:
///
/// * страница портала верстается сборкой, которая вшивает свои CSS и JS
///   прямо в HTML, поэтому `'unsafe-inline'` здесь неизбежен. Ценность
///   остаётся в остальном: чужой скрипт не загрузится (`default-src 'self'`),
///   украденное некуда отправить (`connect-src 'self'`), плагины запрещены,
///   базовый адрес подменить нельзя;
/// * всё остальное — JSON и файлы — не выполняет ничего вообще, и там стоит
///   самая жёсткая политика `default-src 'none'`.
routerUse((e) => {
  const headers = e.response.header();
  headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");

  const path = String(e.request.url.path || "");
  if (path === "/" || path.indexOf("/portal") === 0) {
    headers.set("Content-Security-Policy",
      "default-src 'self'; " +
      "script-src 'self' 'unsafe-inline'; " +
      "style-src 'self' 'unsafe-inline'; " +
      "img-src 'self' data:; " +
      "font-src 'self' data:; " +
      "connect-src 'self'; " +
      "object-src 'none'; " +
      "base-uri 'none'; " +
      "form-action 'self'; " +
      "frame-ancestors 'self'");
  } else {
    headers.set("Content-Security-Policy",
      "default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
  }
  return e.next();
});
