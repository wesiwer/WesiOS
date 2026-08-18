const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");
const horizonTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_horizon_tools.js");
const taskTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_task_tools.js");

const OFFBOARD_COLL = "telegram_offboarded";
const MAX_DELETE_BACKLOG = 600;
const MAX_DELETE_AHEAD = 40;

function nowIso() { return new Date().toISOString(); }

function telegramApi(cfg, method, payload) {
  if (!cfg || !cfg.botToken) return {ok: false, code: "TELEGRAM_NOT_CONFIGURED"};
  let response;
  try {
    response = $http.send({
      url: `https://api.telegram.org/bot${cfg.botToken}/${method}`,
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload || {}),
      timeout: 15,
    });
  } catch (_) {
    return {ok: false, code: "TELEGRAM_UNAVAILABLE"};
  }
  const data = response && response.json && typeof response.json === "object"
    ? response.json
    : {};
  if (!response || response.statusCode < 200 || response.statusCode >= 300 || data.ok !== true) {
    return {
      ok: false,
      code: "TELEGRAM_BAD_RESPONSE",
      description: String(data.description || ""),
    };
  }
  return {ok: true, result: data.result || null};
}

function inlineKeyboard(rows) {
  return rows && rows.length ? {inline_keyboard: rows} : undefined;
}

function visualUrl(cfg, kind) {
  const safe = ["brief", "cash", "risk", "today", "overdue", "push", "farewell"].indexOf(String(kind)) >= 0
    ? String(kind)
    : "brief";
  return `${cfg.publicBaseUrl}/telegram/visuals/${safe}.jpg`;
}

function messageId(result) {
  if (!result || result.ok !== true || !result.result) return 0;
  const id = Number(result.result.message_id || 0);
  return Number.isFinite(id) && id > 0 ? Math.floor(id) : 0;
}

function rememberMessage(app, linkPayload, id, field) {
  const mid = Number(id || 0);
  if (!linkPayload || !Number.isFinite(mid) || mid <= 0) return;
  const key = field || "lastBotMessageId";
  linkPayload[key] = Math.max(Number(linkPayload[key] || 0), Math.floor(mid));
  linkPayload.lastTelegramMessageId = Math.max(
    Number(linkPayload.lastTelegramMessageId || 0),
    Math.floor(mid),
  );
  linkPayload.lastInteractionAt = nowIso();
  store.updateLink(app, linkPayload);
}

function sendPhoto(cfg, chatId, kind, caption, keyboard) {
  const body = {
    chat_id: chatId,
    photo: visualUrl(cfg, kind),
    caption: String(caption || "").slice(0, 1024),
    parse_mode: "HTML",
    protect_content: true,
  };
  const markup = inlineKeyboard(keyboard);
  if (markup) body.reply_markup = markup;
  return telegramApi(cfg, "sendPhoto", body);
}

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function systemFind(app, coll, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: store.SYSTEM_OWNER, coll: coll, rid: rid},
    );
  } catch (_) {
    return null;
  }
}

function systemUpsert(app, coll, rid, payload) {
  let record = systemFind(app, coll, rid);
  if (!record) {
    const collection = app.findCollectionByNameOrId("wesios_records");
    record = new Record(collection);
    record.set("owner", store.SYSTEM_OWNER);
    record.set("org", "wesi-inc");
    record.set("coll", coll);
    record.set("rid", rid);
  }
  record.set("payload", payload || {});
  record.set("stamp", nowIso());
  record.set("deleted", false);
  app.save(record);
}

function systemRemove(app, coll, rid) {
  const record = systemFind(app, coll, rid);
  if (!record) return;
  record.set("deleted", true);
  record.set("stamp", nowIso());
  app.save(record);
}

function offboardRid(telegramUserId) {
  return "tg:" + String(telegramUserId || "");
}

function isOffboarded(app, telegramUserId) {
  return !!systemFind(app, OFFBOARD_COLL, offboardRid(telegramUserId));
}

function commandKind(raw, botUsername) {
  const command = tg.parseCommand(raw || "", botUsername);
  return ["brief", "cash", "risk", "today", "overdue"].indexOf(command.name) >= 0
    ? command.name
    : "";
}

function beforeWebhook(e) {
  const cfg = store.config();
  const update = e.requestInfo().body || {};
  const message = update.message || null;
  const callback = update.callback_query || null;
  const from = message && message.from ? message.from : (callback && callback.from ? callback.from : {});
  const chat = message && message.chat ? message.chat : (callback && callback.message && callback.message.chat ? callback.message.chat : {});
  const telegramUserId = String(from.id || "");
  const chatId = String(chat.id || "");
  if (!telegramUserId || !chatId || String(chat.type || "") !== "private") return {handled: false};

  const parsed = message ? tg.parseCommand(message.text || "", cfg.botUsername) : null;
  if (isOffboarded(e.app, telegramUserId)) {
    // A fresh authenticated WesiOS link code is the only way back after rehire.
    if (parsed && parsed.name === "start" && tg.parseStartCode(parsed)) {
      systemRemove(e.app, OFFBOARD_COLL, offboardRid(telegramUserId));
    } else {
      return {handled: true};
    }
  }

  const link = store.linkByTelegram(e.app, telegramUserId);
  if (!link) return {handled: false};
  const incomingId = Number(
    message && message.message_id ||
    callback && callback.message && callback.message.message_id ||
    0,
  );
  if (incomingId > 0) rememberMessage(e.app, link.payload, incomingId, "lastUserMessageId");

  if (message) {
    const kind = commandKind(message.text || "", cfg.botUsername);
    if (kind) {
      const captions = {
        brief: "<b>WesiOS · Executive Brief</b>\nСобираю ключевую картину бизнеса.",
        cash: "<b>WesiOS · Cash</b>\nПроверяю фактический остаток по доступной организации.",
        risk: "<b>WesiOS · Risk</b>\nПересчитываю runway и кассовый риск.",
        today: "<b>WesiOS · Today</b>\nФокус на задачах текущего дня.",
        overdue: "<b>WesiOS · Overdue</b>\nПоказываю то, что уже требует внимания.",
      };
      const sent = sendPhoto(cfg, chatId, kind, captions[kind], null);
      const mid = messageId(sent);
      if (mid) rememberMessage(e.app, link.payload, mid, "lastBotMessageId");
    }
  }
  return {handled: false};
}

function requestIdentity(e) {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const identity = ai.resolveIdentity(e);
  identity.authUserId = String(e.auth && e.auth.id || "");
  return identity;
}

function testPush(e) {
  const cfg = store.config();
  if (!cfg.ready) return e.json(503, {ok: false, code: "TELEGRAM_NOT_CONFIGURED"});
  const identity = requestIdentity(e);
  const current = store.linkByAuth(e.app, identity.authUserId);
  if (!current) return e.json(404, {ok: false, code: "TELEGRAM_NOT_LINKED"});
  const selected = store.selectVisibleOrganization(e.app, identity, current.payload.activeOrganizationId);
  if (!selected.id) return e.json(403, {ok: false, code: "FORBIDDEN"});
  const sent = sendPhoto(
    cfg,
    current.payload.telegramChatId,
    "push",
    [
      "<b>WesiOS · Test Push</b>",
      "Канал уведомлений работает.",
      "Когда WesiOS заметит важный риск или новую просрочку, уведомление придёт сюда даже при закрытом приложении.",
    ].join("\n"),
    [[{text: "Открыть WesiOS", url: `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=home&org=${encodeURIComponent(selected.id)}`}]],
  );
  if (!sent.ok) return e.json(502, {ok: false, code: sent.code || "TELEGRAM_SEND_FAILED"});
  const mid = messageId(sent);
  if (mid) rememberMessage(e.app, current.payload, mid, "lastBotMessageId");
  return e.json(200, {ok: true, status: "sent", messageId: mid || null});
}

function safeCall(fn) {
  try { return fn(); }
  catch (_) { return {ok: false, code: "DATA_UNAVAILABLE"}; }
}

function timezoneOffset(payload) {
  const prefs = payload && payload.notificationPrefs && typeof payload.notificationPrefs === "object"
    ? payload.notificationPrefs : {};
  return Math.max(-840, Math.min(840, Number(
    prefs.timezoneOffsetMinutes == null
      ? (payload && payload.timezoneOffsetMinutes || 0)
      : prefs.timezoneOffsetMinutes,
  )));
}

function orgName(app, identity, organizationId) {
  const orgs = store.visibleOrganizations(app, identity);
  const hit = orgs.find((item) => String(item.id || "") === String(organizationId || ""));
  return hit ? String(hit.name || hit.id) : String(organizationId || "Организация");
}

function riskSnapshot(event, identity, organizationId) {
  return safeCall(() => horizonTools.execute(event, identity, "horizon_snapshot", {}, organizationId));
}

function dueTasks(event, identity, organizationId, mode, offset) {
  return safeCall(() => taskTools.execute(
    event,
    identity,
    "tasks_list",
    {dueMode: mode, timezoneOffsetMinutes: offset, limit: 5},
    organizationId,
  ));
}

function riskCaption(result, organizationName) {
  const data = result.result || {};
  const risk = tg.riskFromCushionDays(data.cushionDays);
  const cushion = data.cushionDays == null ? "—" : String(data.cushionDays) + " дн.";
  return [
    `<b>WesiOS · ${tg.escapeHtml(organizationName)}</b>`,
    `Кассовый риск: <b>${tg.escapeHtml(risk.label)}</b>`,
    `Запас по текущему темпу: <b>${tg.escapeHtml(cushion)}</b>`,
    "Это автоматический сигнал WesiOS — приложение можно не держать открытым.",
  ].join("\n");
}

function overdueCaption(result, organizationName) {
  const data = result.result || {};
  const tasks = Array.isArray(data.tasks) ? data.tasks : [];
  const total = Math.max(0, Number(data.totalCount == null ? tasks.length : data.totalCount));
  const lines = [
    `<b>WesiOS · ${tg.escapeHtml(organizationName)}</b>`,
    `Просроченных задач: <b>${total}</b>`,
  ];
  for (const task of tasks.slice(0, 5)) {
    lines.push(`• ${tg.escapeHtml(String(task.title || "Без названия").slice(0, 120))}`);
  }
  return lines.join("\n");
}

function runNotifier(eventOrApp) {
  const app = eventOrApp && eventOrApp.app ? eventOrApp.app : eventOrApp;
  if (!app) return;
  const cfg = store.config();
  if (!cfg.ready) return;
  const links = store.rows(app, store.COLL_LINKS, 5000);
  for (const row of links) {
    const payload = store.payloadOf(row);
    if (!payload || payload.revokedAt || !payload.telegramUserId || !payload.telegramChatId || !payload.authUserId) continue;
    const identity = store.resolveIdentityForAuth(app, payload.authUserId);
    if (!identity) {
      offboardByAuth(app, payload.authUserId, "identity-invalid");
      continue;
    }
    const selected = store.selectVisibleOrganization(app, identity, payload.activeOrganizationId);
    if (!selected.id) continue;
    payload.activeOrganizationId = selected.id;

    const prefs = payload.notificationPrefs && typeof payload.notificationPrefs === "object"
      ? payload.notificationPrefs : {};
    const state = payload.alertState && typeof payload.alertState === "object"
      ? payload.alertState : {};
    const offset = timezoneOffset(payload);
    const quiet = tg.isQuietHours(Date.now(), offset, prefs.quietFromHour, prefs.quietToHour);
    const event = {app: app};

    const riskResult = riskSnapshot(event, identity, selected.id);
    if (riskResult.ok === true) {
      const risk = tg.riskFromCushionDays(riskResult.result.cushionDays);
      if (prefs.risk === false) {
        state.riskLevel = risk.level;
      } else if (!quiet && tg.shouldNotifyRisk(state.riskLevel, risk.level)) {
        const sent = sendPhoto(
          cfg,
          payload.telegramChatId,
          "risk",
          riskCaption(riskResult, orgName(app, identity, selected.id)),
          [[{text: "Открыть риск", callback_data: tg.callback("risk", "")}]],
        );
        if (sent.ok === true) {
          state.riskLevel = risk.level;
          const mid = messageId(sent);
          if (mid) payload.lastBotMessageId = Math.max(Number(payload.lastBotMessageId || 0), mid);
        }
      }
    }

    const overdue = dueTasks(event, identity, selected.id, "overdue", offset);
    if (overdue.ok === true) {
      const count = Math.max(0, Number(overdue.result.totalCount || 0));
      if (prefs.overdue === false) {
        state.overdueCount = count;
      } else if (!quiet && tg.shouldNotifyOverdue(state.overdueCount, count)) {
        const sent = sendPhoto(
          cfg,
          payload.telegramChatId,
          "overdue",
          overdueCaption(overdue, orgName(app, identity, selected.id)),
          [[{text: "Открыть задачи", url: `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=tasks&org=${encodeURIComponent(selected.id)}`}]],
        );
        if (sent.ok === true) {
          state.overdueCount = count;
          const mid = messageId(sent);
          if (mid) payload.lastBotMessageId = Math.max(Number(payload.lastBotMessageId || 0), mid);
        }
      }
    }

    payload.lastTelegramMessageId = Math.max(
      Number(payload.lastTelegramMessageId || 0),
      Number(payload.lastBotMessageId || 0),
      Number(payload.lastUserMessageId || 0),
    );
    payload.alertState = state;
    payload.lastNotifierAt = nowIso();
    store.updateLink(app, payload);
  }
}

function deleteRecentHistory(cfg, chatId, anchor) {
  const last = Math.max(0, Math.floor(Number(anchor || 0)));
  if (!last || !chatId) return;
  const first = Math.max(1, last - MAX_DELETE_BACKLOG);
  const end = last + MAX_DELETE_AHEAD;
  let batch = [];
  for (let id = first; id <= end; id++) {
    batch.push(id);
    if (batch.length === 100 || id === end) {
      telegramApi(cfg, "deleteMessages", {chat_id: chatId, message_ids: batch});
      batch = [];
    }
  }
}

function farewellCaption(firstName) {
  const hello = String(firstName || "").trim()
    ? `${tg.escapeHtml(String(firstName).trim())}, эта глава нашей общей истории подходит к концу.`
    : "Эта глава нашей общей истории подходит к концу.";
  return [
    `<b>${hello}</b>`,
    "",
    "Нам искренне жаль прощаться. Спасибо за время, идеи, решения и дни, которые вы разделили с командой. За любой компанией всегда стоят люди — и часть того, чем она стала, теперь навсегда связана и с вами.",
    "",
    "Доступ к рабочему пространству WesiOS закрыт. Но хорошие моменты совместной работы не исчезают вместе с доступом — они остаются частью пути, который мы прошли рядом.",
    "",
    "Пусть дальше будут люди, с которыми хочется создавать, работа, которой можно гордиться, и место, где ваши сильные стороны будут по-настоящему нужны.",
    "",
    "Берегите себя. Желаем вам всего самого лучшего. И спасибо, что были с нами.",
    "",
    "<i>— Команда WesiOS</i>",
  ].join("\n");
}

function offboardByAuth(app, authUserId, reason) {
  const current = store.linkByAuth(app, authUserId);
  if (!current) return {ok: false, code: "NOT_LINKED"};
  const payload = Object.assign({}, current.payload || {});
  const cfg = store.config();
  const chatId = String(payload.telegramChatId || "");
  const telegramUserId = String(payload.telegramUserId || "");
  const anchor = Math.max(
    Number(payload.lastTelegramMessageId || 0),
    Number(payload.lastBotMessageId || 0),
    Number(payload.lastUserMessageId || 0),
  );

  // Revoke first. Any command racing with cleanup loses authorization immediately.
  store.revokeByAuth(app, authUserId, reason || "employee-offboarded");
  if (telegramUserId) {
    systemUpsert(app, OFFBOARD_COLL, offboardRid(telegramUserId), {
      telegramUserId: telegramUserId,
      authUserId: String(authUserId || ""),
      ownerId: String(payload.ownerId || ""),
      employeeId: String(payload.employeeId || ""),
      offboardedAt: nowIso(),
      reason: String(reason || "employee-offboarded").slice(0, 120),
    });
  }
  if (!cfg.ready || !chatId) return {ok: true, delivered: false};

  deleteRecentHistory(cfg, chatId, anchor);
  const farewell = sendPhoto(
    cfg,
    chatId,
    "farewell",
    farewellCaption(payload.telegramFirstName),
    null,
  );
  return {ok: true, delivered: farewell.ok === true};
}

function offboardEmployee(app, ownerId, employeeId, reason) {
  const owner = String(ownerId || "");
  const employee = String(employeeId || "");
  if (!owner || !employee || employee === "owner") return 0;
  let count = 0;
  const links = store.rows(app, store.COLL_LINKS, 5000);
  for (const row of links) {
    const p = store.payloadOf(row);
    if (!p || p.revokedAt) continue;
    if (String(p.ownerId || "") !== owner || String(p.employeeId || "") !== employee) continue;
    const result = offboardByAuth(app, p.authUserId, reason || "employee-offboarded");
    if (result && result.ok) count++;
  }
  return count;
}

function isInactiveEmployeeRecord(record, physicallyDeleted) {
  if (!record) return false;
  let coll = "";
  let softDeleted = false;
  try { coll = String(record.getString("coll") || ""); } catch (_) {}
  if (coll !== "employees") return false;
  try { softDeleted = record.getBool("deleted") === true; } catch (_) {}
  const p = payloadOf(record);
  const status = String(p.status || "active").trim().toLowerCase();
  return physicallyDeleted === true || softDeleted || p.deleted === true || p.active === false ||
    p.deactivated === true || p.disabled === true ||
    ["inactive", "disabled", "deactivated", "archived", "terminated", "fired", "dismissed", "removed", "deleted", "уволен", "увольнение"].indexOf(status) >= 0;
}

function handleEmployeeRecord(app, record, physicallyDeleted) {
  if (!isInactiveEmployeeRecord(record, physicallyDeleted)) return 0;
  let ownerId = "";
  let employeeId = "";
  try { ownerId = String(record.getString("owner") || ""); } catch (_) {}
  try { employeeId = String(record.getString("rid") || ""); } catch (_) {}
  if (!employeeId) employeeId = String(payloadOf(record).id || "");
  return offboardEmployee(app, ownerId, employeeId, "employee-offboarded");
}

module.exports = {
  beforeWebhook,
  testPush,
  runNotifier,
  offboardByAuth,
  offboardEmployee,
  handleEmployeeRecord,
  deleteRecentHistory,
};
