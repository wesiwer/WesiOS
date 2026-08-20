// PocketBase serializes each route/cron handler into an isolated JS program.
// Keep handlers self-contained where cache freshness matters. Telegram account
// linking is deliberately implemented inline below so a stale CommonJS module
// cache cannot reuse an older TTL implementation after a hot hook deployment.

routerAdd("POST", "/api/wesi/telegram/link/create", (e) => {
  const store = require(`${__hooks}/wesi_telegram_store.js`);
  const cfg = store.config();
  if (!cfg.ready) {
    return e.json(503, {ok: false, code: "TELEGRAM_NOT_CONFIGURED"});
  }

  const authUserId = String(e.auth && e.auth.id || "");
  const identity = store.resolveIdentityForAuth(e.app, authUserId);
  if (!identity) {
    return e.json(403, {ok: false, code: "FORBIDDEN", message: "Аккаунт WesiOS недоступен"});
  }
  if (store.linkByAuth(e.app, authUserId)) {
    return e.json(409, {ok: false, code: "TELEGRAM_ALREADY_LINKED"});
  }

  const body = e.requestInfo().body || {};
  const requestedOrganizationId = String(body.activeOrganizationId || "");
  const selected = store.selectVisibleOrganization(e.app, identity, requestedOrganizationId);
  if (!selected.id || (requestedOrganizationId && selected.id !== requestedOrganizationId)) {
    return e.json(403, {ok: false, code: "FORBIDDEN", message: "Нет доступа к этой организации"});
  }

  let botResponse;
  try {
    botResponse = $http.send({
      url: `https://api.telegram.org/bot${cfg.botToken}/getMe`,
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: "{}",
      timeout: 12,
    });
  } catch (_) {
    return e.json(502, {
      ok: false,
      code: "TELEGRAM_BOT_IDENTITY_UNAVAILABLE",
      message: "Не удалось проверить имя Telegram-бота. Повторите попытку позже.",
    });
  }
  const botData = botResponse && botResponse.json && typeof botResponse.json === "object"
    ? botResponse.json
    : {};
  const botUsername = botData.ok === true && botData.result
    ? String(botData.result.username || "").replace(/^@/, "")
    : "";
  if (!/^[A-Za-z0-9_]{5,32}$/.test(botUsername)) {
    return e.json(502, {
      ok: false,
      code: "TELEGRAM_BOT_IDENTITY_UNAVAILABLE",
      message: "Не удалось проверить имя Telegram-бота. Повторите попытку позже.",
    });
  }

  const nowMs = Date.now();
  const ttlMs = 10 * 60 * 1000;
  const expiresAtMs = nowMs + ttlMs;
  const code = $security.randomStringWithAlphabet(
    28,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
  );
  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const record = new Record(collection);
  record.set("owner", "__wesios_telegram__");
  record.set("org", "wesi-inc");
  record.set("coll", "telegram_link_codes");
  record.set("rid", "code:" + $security.sha256(code));
  record.set("payload", {
    authUserId: identity.authUserId,
    ownerId: identity.ownerId,
    employeeId: identity.employeeId,
    isOwner: identity.isOwner === true,
    activeOrganizationId: selected.id,
    timezoneOffsetMinutes: Math.max(
      -840,
      Math.min(840, Number(body.timezoneOffsetMinutes || 0)),
    ),
    createdAtMs: nowMs,
    expiresAtMs: expiresAtMs,
    createdAt: new Date(nowMs).toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString(),
    runtimeVersion: 3,
  });
  record.set("stamp", new Date(nowMs).toISOString());
  record.set("deleted", false);
  e.app.save(record);

  return e.json(200, {
    ok: true,
    linked: false,
    code: code,
    expiresAt: new Date(expiresAtMs).toISOString(),
    botUsername: botUsername,
    deepLink: `https://t.me/${botUsername}?start=${encodeURIComponent(code)}`,
    activeOrganizationId: selected.id,
  });
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/telegram/status", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.status(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/revoke", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.revoke(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/context", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.context(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/preferences", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.preferences(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/test-push", (e) => {
  const experience = require(`${__hooks}/wesi_telegram_experience.js`);
  return experience.testPush(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/telegram/open", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.open(e);
});

routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {
  // Linking is handled before the cached gateway. Both the one-time ticket and
  // its TTL are read directly from PocketBase, so an older require() cache
  // cannot turn a freshly issued code into an immediately expired one.
  try {
    const store = require(`${__hooks}/wesi_telegram_store.js`);
    const cfg = store.config();
    const secret = String(e.request.header.get("X-Telegram-Bot-Api-Secret-Token") || "");
    if (!cfg.ready || !secret || !$security.equal(secret, cfg.webhookSecret)) {
      return e.json(401, {ok: false, code: "UNAUTHORIZED"});
    }

    const update = e.requestInfo().body || {};
    const message = update.message || null;
    const type = String(message && message.chat && message.chat.type || "");
    const text = String(message && message.text || "").trim();
    const start = type === "private"
      ? text.match(/^\/start(?:@[A-Za-z0-9_]+)?\s+([A-Za-z0-9_-]{20,64})\s*$/)
      : null;

    if (start) {
      const code = String(start[1] || "");
      const chatId = String(message && message.chat && message.chat.id || "");
      const from = message && message.from || {};
      const telegramUserId = String(from.id || "");
      const send = (textValue) => {
        try {
          $http.send({
            url: `https://api.telegram.org/bot${cfg.botToken}/sendMessage`,
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({chat_id: chatId, text: String(textValue || "").slice(0, 4096)}),
            timeout: 12,
          });
        } catch (_) {}
      };

      const rows = e.app.findRecordsByFilter(
        "wesios_records",
        "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
        "id",
        1,
        0,
        {
          owner: "__wesios_telegram__",
          coll: "telegram_link_codes",
          rid: "code:" + $security.sha256(code),
        },
      );
      const record = rows.length ? rows[0] : null;
      if (!record) {
        send("Код привязки недействителен. Создайте новый в WesiOS.");
        return e.json(200, {ok: true});
      }

      let payload = {};
      try {
        const raw = record.get("payload");
        payload = raw && typeof raw === "object" && !Array.isArray(raw)
          ? raw
          : (typeof raw === "string" && raw.trim() ? JSON.parse(raw) : {});
      } catch (_) {
        payload = {};
      }

      const nowMs = Date.now();
      const expiresAtMs = Number(payload.expiresAtMs);
      const validNumericTtl = Number.isFinite(expiresAtMs) && expiresAtMs > nowMs;
      if (!validNumericTtl) {
        record.set("deleted", true);
        record.set("stamp", new Date(nowMs).toISOString());
        e.app.save(record);
        send("Код привязки истёк. Создайте новый в WesiOS.");
        return e.json(200, {ok: true});
      }

      // Consume before any identity/link checks. A one-time ticket cannot be
      // replayed even if a later permission check rejects the account.
      record.set("deleted", true);
      record.set("stamp", new Date(nowMs).toISOString());
      e.app.save(record);

      const identity = store.resolveIdentityForAuth(e.app, String(payload.authUserId || ""));
      if (!identity) {
        send("Аккаунт WesiOS больше недоступен. Войдите в приложение и создайте новую привязку.");
        return e.json(200, {ok: true});
      }

      const alreadyTelegram = store.linkByTelegram(e.app, telegramUserId);
      if (alreadyTelegram &&
          String(alreadyTelegram.payload.authUserId || "") !== String(identity.authUserId || "")) {
        send("Этот Telegram уже привязан к другому аккаунту WesiOS. Сначала отвяжите его там.");
        return e.json(200, {ok: true});
      }
      const alreadyAuth = store.linkByAuth(e.app, identity.authUserId);
      if (alreadyAuth && String(alreadyAuth.payload.telegramUserId || "") !== telegramUserId) {
        send("Аккаунт WesiOS уже привязан к другому Telegram. Отзовите старую привязку в приложении.");
        return e.json(200, {ok: true});
      }

      const selected = store.selectVisibleOrganization(
        e.app,
        identity,
        String(payload.activeOrganizationId || ""),
      );
      if (!selected.id ||
          (payload.activeOrganizationId && selected.id !== String(payload.activeOrganizationId))) {
        send("Привязка не завершена: у аккаунта нет доступа к выбранной организации.");
        return e.json(200, {ok: true});
      }

      const saved = store.saveLink(e.app, {
        authUserId: identity.authUserId,
        ownerId: identity.ownerId,
        employeeId: identity.employeeId,
        isOwner: identity.isOwner === true,
        telegramUserId: telegramUserId,
        telegramChatId: chatId,
        telegramUsername: String(from.username || ""),
        telegramFirstName: String(from.first_name || "").slice(0, 120),
        activeOrganizationId: selected.id,
        timezoneOffsetMinutes: Number(payload.timezoneOffsetMinutes || 0),
      });
      const organization = selected.organizations.find((item) =>
        String(item.id || "") === String(saved.activeOrganizationId || ""));
      send(
        "WesiOS подключён.\n" +
        "Организация: " + String(organization && organization.name || saved.activeOrganizationId || "WesiOS") + "\n" +
        "Права берутся из WesiOS при каждом запросе. Отвязка в приложении блокирует бот сразу.",
      );
      return e.json(200, {ok: true});
    }
  } catch (_) {
    // If this is not a link update, fall through to the regular interaction
    // pipeline. Unexpected link-preflight failures are acknowledged by the
    // existing gateway, which prevents Telegram retry storms.
  }

  // Capture the exact incoming message id and opportunistically remove any
  // WesiOS chat messages whose 24-hour retention window has expired.
  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    interactions.captureIncoming(e);
  } catch (_) {}

  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    const preflight = experience.beforeWebhook(e);
    if (preflight && preflight.handled === true) {
      return e.json(200, {ok: true});
    }
  } catch (_) {}

  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    const interaction = interactions.handle(e);
    if (interaction && interaction.handled === true) {
      return e.json(200, {ok: true});
    }
  } catch (_) {}

  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.webhook(e);
});

cronAdd("wesios_telegram_alerts_v2", "*/5 * * * *", () => {
  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    interactions.cleanupRetention($app);
  } catch (_) {}
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.runNotifier($app);
  } catch (_) {}
  try {
    const morning = require(`${__hooks}/wesi_telegram_morning.js`);
    morning.runMorning($app);
  } catch (_) {}
});

onRecordAfterDeleteSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.offboardByAuth(e.app, e.record.id, "employee-account-deleted");
  } catch (_) {}
  e.next();
}, "users");

onRecordAfterUpdateSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.handleEmployeeRecord(e.app, e.record, false);
  } catch (_) {}
  e.next();
}, "wesios_records");

onRecordAfterDeleteSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.handleEmployeeRecord(e.app, e.record, true);
  } catch (_) {}
  e.next();
}, "wesios_records");
