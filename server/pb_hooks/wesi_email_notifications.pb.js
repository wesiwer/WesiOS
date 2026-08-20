const DELIVERY_OWNER = "__wesios_email_notifications__";
const DELIVERY_COLL = "email_delivery";
const MAX_TITLE = 180;
const MAX_BODY = 4000;

function text(value) {
  return String(value == null ? "" : value).trim();
}

function validEmail(value) {
  const email = text(value).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : "";
}

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object") return raw;
    if (typeof raw === "string" && raw.trim()) {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" ? parsed : {};
    }
  } catch (_) {}
  return {};
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function asciiHtml(value) {
  return String(value || "").replace(/[^\x00-\x7F]/g, (character) =>
    "&#" + character.charCodeAt(0) + ";"
  );
}

function readMailConfig() {
  try {
    const raw = $os.readFile(__hooks + "/.wesi-mail.json");
    const rawText = typeof raw === "string"
      ? raw
      : String.fromCharCode.apply(null, raw || []);
    const parsed = JSON.parse(rawText || "{}");
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (_) {
    return {};
  }
}

function envRead(name) {
  try {
    return text($os.getenv(name));
  } catch (_) {
    return "";
  }
}

function sendMail(app, email, displayName, subject, html, plainText) {
  const settings = app.settings();
  const senderAddress = text(settings && settings.meta && settings.meta.senderAddress) || "no-reply@wesi-inc.ru";
  const senderName = text(settings && settings.meta && settings.meta.senderName) || "WesiOS";
  const message = new MailerMessage({
    from: {address: senderAddress, name: senderName},
    to: [{address: email, name: displayName}],
    subject: subject,
    html: asciiHtml(html),
    text: plainText,
  });

  try {
    app.newMailClient().send(message);
    return "pocketbase";
  } catch (error) {
    console.log("WesiOS notification mail via PocketBase failed, trying HTTPS provider:", error);
  }

  const config = readMailConfig();
  const provider = text(config.provider).toLowerCase();
  const apiKey = text(config.apiKey) || envRead("WESIOS_RESEND_API_KEY") || envRead("RESEND_API_KEY");
  const from = text(config.from) || envRead("WESIOS_RESEND_FROM") || envRead("RESEND_FROM");
  if ((provider && provider !== "resend") || !apiKey || !from) {
    throw new Error("No working WesiOS mail transport configured");
  }

  const response = $http.send({
    url: "https://api.resend.com/emails",
    method: "POST",
    headers: {
      Authorization: "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: from,
      to: [email],
      subject: subject,
      html: asciiHtml(html),
      text: plainText,
    }),
    timeout: 20,
  });
  if (!response || response.statusCode < 200 || response.statusCode >= 300) {
    const statusCode = response && response.statusCode ? response.statusCode : 0;
    throw new Error("HTTPS mail provider returned HTTP " + statusCode);
  }
  return "https";
}

function requireWesiSession(e) {
  const sid = text(e.request.header.get("X-WesiOS-Session"));
  if (!/^[A-Za-z0-9_-]{24,96}$/.test(sid)) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }

  const session = require(`${__hooks}/wesi_sync_data_access.js`).first(
    e.app,
    "wesios_records",
    "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false",
    {rid: "session:" + sid},
  );
  if (!session) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }

  let sessionPayload = {};
  try {
    const model = new DynamicModel({
      userId: "",
      expiresAt: "",
      revokedAt: "",
    });
    session.unmarshalJSONField("payload", model);
    sessionPayload = {
      userId: text(model.userId),
      expiresAt: text(model.expiresAt),
      revokedAt: text(model.revokedAt),
    };
  } catch (_) {
    sessionPayload = {};
  }

  const expiresAt = Date.parse(text(sessionPayload.expiresAt));
  const authUserId = text(e.auth && e.auth.id);
  if (!authUserId ||
      sessionPayload.userId !== authUserId ||
      sessionPayload.revokedAt ||
      !Number.isFinite(expiresAt) ||
      expiresAt <= Date.now()) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }
  return sid;
}

function findEmployee(app, identity) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
      {owner: identity.ownerId, rid: identity.employeeId},
    );
  } catch (_) {
    return null;
  }
}

function findDelivery(app, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: DELIVERY_OWNER, coll: DELIVERY_COLL, rid: rid},
    );
  } catch (_) {
    return null;
  }
}

function createDelivery(app, authUserId, identity, notificationId) {
  const collection = app.findCollectionByNameOrId("wesios_records");
  const record = new Record(collection);
  const now = new Date().toISOString();
  record.set("owner", DELIVERY_OWNER);
  record.set("org", "wesi-inc");
  record.set("coll", DELIVERY_COLL);
  record.set("rid", "email:" + $security.sha256(authUserId + ":" + notificationId));
  record.set("payload", {
    authUserId: authUserId,
    ownerId: identity.ownerId,
    employeeId: identity.employeeId,
    notificationId: notificationId,
    status: "sending",
    createdAt: now,
  });
  record.set("stamp", now);
  record.set("deleted", false);
  app.save(record);
  return record;
}

function mailMarkup(title, body, kind) {
  const safeTitle = escapeHtml(title);
  const safeBody = escapeHtml(body).replace(/\r?\n/g, "<br>");
  const safeKind = escapeHtml(kind || "notification");
  const html = "<!doctype html>" +
    "<html lang=\"ru\"><head><meta charset=\"utf-8\">" +
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
    "<meta name=\"color-scheme\" content=\"dark\">" +
    "<title>WesiOS · " + safeTitle + "</title></head>" +
    "<body style=\"margin:0;padding:0;background:#09090B;color:#F7F7F8;\">" +
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"#09090B\" style=\"width:100%;background:#09090B;\">" +
    "<tr><td align=\"center\" style=\"padding:32px 16px;\">" +
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"#121216\" style=\"width:100%;max-width:560px;background:#121216;border:1px solid #29292F;border-radius:24px;overflow:hidden;\">" +
    "<tr><td height=\"4\" bgcolor=\"#F97316\" style=\"height:4px;background:#F97316;font-size:0;line-height:0;\">&nbsp;</td></tr>" +
    "<tr><td style=\"padding:28px 32px 12px;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
    "<div style=\"font-size:20px;line-height:24px;font-weight:700;color:#FFFFFF;\">WesiOS</div>" +
    "<div style=\"margin-top:4px;font-size:10px;line-height:14px;font-weight:700;letter-spacing:1.5px;color:#84CC16;\">SERVER NOTIFICATION</div>" +
    "</td></tr>" +
    "<tr><td style=\"padding:18px 32px 8px;font-family:Arial,'Helvetica Neue',sans-serif;\">" +
    "<h1 style=\"margin:0;font-size:27px;line-height:34px;font-weight:750;color:#FFFFFF;\">" + safeTitle + "</h1>" +
    "</td></tr>" +
    "<tr><td style=\"padding:10px 32px 28px;font-family:Arial,'Helvetica Neue',sans-serif;font-size:16px;line-height:25px;color:#C7C7CF;\">" + safeBody + "</td></tr>" +
    "<tr><td style=\"padding:16px 32px 22px;border-top:1px solid #29292F;font-family:Arial,'Helvetica Neue',sans-serif;font-size:11px;line-height:18px;color:#777781;\">" +
    "Тип: <span style=\"color:#A5A5AE;\">" + safeKind + "</span><br>Это автоматическое письмо от сервера WesiOS. Отвечать на него не нужно." +
    "</td></tr></table>" +
    "</td></tr></table></body></html>";
  return html;
}

routerAdd("POST", "/api/wesi/notifications/email", (e) => {
  requireWesiSession(e);
  const store = require(`${__hooks}/wesi_telegram_store.js`);
  const authUserId = text(e.auth && e.auth.id);
  const identity = store.resolveIdentityForAuth(e.app, authUserId);
  if (!identity) {
    return e.json(403, {ok: false, code: "IDENTITY_NOT_RESOLVED"});
  }

  const body = e.requestInfo().body || {};
  const notificationId = text(body.id).slice(0, 220);
  const title = text(body.title).slice(0, MAX_TITLE);
  const notificationBody = text(body.body).slice(0, MAX_BODY);
  const kind = text(body.kind).slice(0, 40);
  if (!notificationId || !title) {
    return e.json(400, {ok: false, code: "INVALID_NOTIFICATION"});
  }

  const employee = findEmployee(e.app, identity);
  if (!employee) {
    return e.json(422, {ok: false, code: "EMPLOYEE_CARD_MISSING"});
  }
  const employeePayload = payloadOf(employee);
  const email = validEmail(employeePayload.email);
  if (!email) {
    return e.json(422, {ok: false, code: "EMPLOYEE_EMAIL_MISSING"});
  }
  const displayName = text(employeePayload.fullName || employeePayload.name || "WesiOS");

  const deliveryRid = "email:" + $security.sha256(authUserId + ":" + notificationId);
  const previous = findDelivery(e.app, deliveryRid);
  if (previous) {
    return e.json(200, {ok: true, duplicate: true});
  }

  let delivery = null;
  try {
    delivery = createDelivery(e.app, authUserId, identity, notificationId);
  } catch (error) {
    if (findDelivery(e.app, deliveryRid)) {
      return e.json(200, {ok: true, duplicate: true});
    }
    throw error;
  }

  const subject = "[WesiOS] " + title;
  const html = mailMarkup(title, notificationBody, kind);
  const plain = title + (notificationBody ? "\n\n" + notificationBody : "") +
    (kind ? "\n\nТип: " + kind : "") +
    "\n\nЭто автоматическое письмо от сервера WesiOS. Отвечать на него не нужно.";

  try {
    const method = sendMail(e.app, email, displayName, subject, html, plain);
    const payload = payloadOf(delivery);
    payload.status = "sent";
    payload.method = method;
    payload.sentAt = new Date().toISOString();
    payload.recipientHash = $security.sha256(email.toLowerCase());
    delivery.set("payload", payload);
    delivery.set("stamp", payload.sentAt);
    e.app.save(delivery);
    return e.json(200, {ok: true, duplicate: false, method: method});
  } catch (error) {
    try { e.app.delete(delivery); } catch (_) {}
    console.log("WesiOS notification email delivery failed:", error);
    return e.json(503, {ok: false, code: "EMAIL_DELIVERY_FAILED"});
  }
}, $apis.requireAuth("users"));
