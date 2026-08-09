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
    "version": "2026-08-09.owner-email-v6",
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

const WESI_MAIL_TEMPLATE_VERSION = "2026-08-09.mail-design-v1";
const WESI_MAIL_LOGO_URL = "https://api.wesi-inc.ru/portal/app_icon.png";

/// Transactional email markup intentionally uses tables and inline styles.
/// This keeps the dark WesiOS design stable in Gmail, Apple Mail, Outlook,
/// and narrow mobile clients without relying on external fonts or scripts.
const wesiBuildOtpMail = (code, purpose) => {
  const safeCode = String(code || "").replace(/[^0-9]/g, "");
  const emailSetup = purpose === "email-setup";
  const portal = purpose === "portal";
  const title = emailSetup ? "Подтверждение почты" : "Подтверждение входа";
  const eyebrow = emailSetup ? "БЕЗОПАСНОСТЬ АККАУНТА" : "КОД БЕЗОПАСНОСТИ";
  const lead = emailSetup
    ? "Введите этот код, чтобы подтвердить адрес почты и завершить защищённый вход."
    : portal
      ? "Введите этот код на портале WesiOS, чтобы продолжить вход."
      : "Введите этот код в приложении WesiOS, чтобы продолжить вход.";
  const preheader = emailSetup
    ? "Подтвердите адрес почты в WesiOS. Код действует 10 минут."
    : "Код подтверждения входа в WesiOS действует 10 минут.";
  const textLead = emailSetup
    ? "Код подтверждения почты и входа"
    : portal
      ? "Код входа на портал WesiOS"
      : "Код входа в WesiOS";

  const html = "<!doctype html>" +
    "<html lang=\"ru\"><head><meta charset=\"utf-8\">" +
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
    "<meta name=\"color-scheme\" content=\"dark\">" +
    "<meta name=\"supported-color-schemes\" content=\"dark\">" +
    "<meta name=\"x-wesios-template\" content=\"" + WESI_MAIL_TEMPLATE_VERSION + "\">" +
    "<title>" + title + " · WesiOS</title>" +
    "<style>@media only screen and (max-width:620px){" +
    ".wesi-shell{padding:16px!important}.wesi-card{border-radius:20px!important}" +
    ".wesi-pad{padding-left:24px!important;padding-right:24px!important}" +
    ".wesi-code{font-size:36px!important;letter-spacing:7px!important}" +
    "}</style></head>" +
    "<body style=\"margin:0;padding:0;background:#09090B;color:#F7F7F8;\">" +
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;\">" +
    preheader + "&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;</div>" +
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#09090B\" style=\"width:100%;background:#09090B;\">" +
    "<tr><td class=\"wesi-shell\" align=\"center\" style=\"padding:36px 16px;\">" +
    "<table role=\"presentation\" class=\"wesi-card\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" bgcolor=\"#121216\" style=\"width:100%;max-width:560px;background:#121216;border:1px solid #29292F;border-radius:28px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.35);\">" +
    "<tr><td height=\"4\" bgcolor=\"#F97316\" style=\"height:4px;background:#F97316;font-size:0;line-height:0;\">&nbsp;</td></tr>" +
    "<tr><td class=\"wesi-pad\" style=\"padding:30px 36px 16px;\">" +
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr>" +
    "<td width=\"64\" valign=\"middle\"><img src=\"" + WESI_MAIL_LOGO_URL + "\" width=\"56\" height=\"56\" alt=\"WesiOS\" style=\"display:block;width:56px;height:56px;border:0;border-radius:16px;\"></td>" +
    "<td valign=\"middle\" style=\"padding-left:14px;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
    "<div style=\"font-size:20px;line-height:24px;font-weight:700;letter-spacing:.2px;color:#FFFFFF;\">WesiOS</div>" +
    "<div style=\"margin-top:4px;font-size:11px;line-height:15px;font-weight:700;letter-spacing:1.5px;color:#84CC16;\">SECURITY CENTER</div>" +
    "</td></tr></table></td></tr>" +
    "<tr><td class=\"wesi-pad\" style=\"padding:22px 36px 0;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
    "<div style=\"font-size:11px;line-height:16px;font-weight:700;letter-spacing:1.6px;color:#F97316;\">" + eyebrow + "</div>" +
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

  return {"html": html, "text": text};
};

const wesiDeliverMail = (app, email, displayName, subject, html, text) => {
  const settings = app.settings();
  const smtpSelected = Boolean(
    settings && settings.smtp && settings.smtp.enabled === true &&
    String(settings.smtp.host || "").trim(),
  );

  // PocketBase selects the configured SMTP client when SMTP is enabled and
  // the local sendmail command otherwise. Always let PocketBase choose first;
  // the old smtpReady guard accidentally disabled the safe sendmail fallback.
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
    return smtpSelected ? "smtp" : "sendmail";
  } catch (error) {
    console.log("WesiOS PocketBase mail client failed, trying HTTPS provider:", error);
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
    const mail = wesiBuildOtpMail(code, purpose);
    try {
      payload.delivery = wesiDeliverMail(e.app, email, displayName, subject, mail.html, mail.text);
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
    throw new ForbiddenError("Проверка привязки не соответствует профилю владельца [owner-email-v6]");
  }
  let ownerMarker = null;
  try {
    ownerMarker = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + String(payload.userId || "") + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) { ownerMarker = null; }
  if (!ownerMarker) {
    throw new ForbiddenError("Профиль владельца не закреплён [owner-email-v6]");
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
  const mail = wesiBuildOtpMail(code, "email-setup");
  try {
    payload.delivery = wesiDeliverMail(
      e.app,
      email,
      user.getString("name") || String(payload.login || "WesiOS"),
      subject,
      mail.html,
      mail.text,
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
    "authVersion": "2026-08-09.owner-email-v6",
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
