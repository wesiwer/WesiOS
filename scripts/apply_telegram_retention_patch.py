from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one patch target, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


interactions = r'''const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");

const RETENTION_COLL = "telegram_retention";
const RETENTION_TTL_MS = 24 * 60 * 60 * 1000;
const RETENTION_MAX_ROWS = 5000;

function nowIso() { return new Date().toISOString(); }

function retentionRid(chatId, messageId) {
  return `msg:${String(chatId || "")}:${String(messageId || "")}`;
}

function retentionDueAt(createdAt) {
  const parsed = Date.parse(String(createdAt || ""));
  const base = Number.isFinite(parsed) ? parsed : Date.now();
  return new Date(base + RETENTION_TTL_MS).toISOString();
}

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
  const data = response && response.json && typeof response.json === "object" ? response.json : {};
  if (!response || response.statusCode < 200 || response.statusCode >= 300 || data.ok !== true) {
    return {
      ok: false,
      code: "TELEGRAM_BAD_RESPONSE",
      description: String(data.description || ""),
    };
  }
  return {ok: true, result: data.result || null};
}

function activePrivateLink(app, chatId) {
  const id = String(chatId || "");
  if (!app || !/^[1-9][0-9]*$/.test(id)) return null;
  try { return store.linkByTelegram(app, id); }
  catch (_) { return null; }
}

function retentionFind(app, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: store.SYSTEM_OWNER, coll: RETENTION_COLL, rid: rid},
    );
  } catch (_) {
    return null;
  }
}

function trackTelegramMessage(app, chatId, messageId, direction) {
  const chat = String(chatId || "");
  const mid = Math.floor(Number(messageId || 0));
  if (!chat || !Number.isFinite(mid) || mid <= 0) return false;

  // Retention is a WesiOS workspace policy, not a blanket Telegram policy.
  // No active WesiOS link means no new TTL record. This is intentional:
  // after offboarding the link is revoked before the farewell is sent, so the
  // farewell is never queued for deletion and remains as the final memory.
  if (!activePrivateLink(app, chat)) return false;

  const rid = retentionRid(chat, mid);
  let record = retentionFind(app, rid);
  let previous = {};
  if (record) previous = store.payloadOf(record);
  const createdAt = String(previous.createdAt || nowIso());
  if (!record) {
    const collection = app.findCollectionByNameOrId("wesios_records");
    record = new Record(collection);
    record.set("owner", store.SYSTEM_OWNER);
    record.set("org", "wesi-inc");
    record.set("coll", RETENTION_COLL);
    record.set("rid", rid);
  }
  record.set("payload", {
    chatId: chat,
    messageId: mid,
    direction: String(previous.direction || direction || "unknown").slice(0, 20),
    createdAt: createdAt,
    deleteAfter: String(previous.deleteAfter || retentionDueAt(createdAt)),
    preserve: false,
  });
  record.set("stamp", nowIso());
  record.set("deleted", false);
  app.save(record);
  return true;
}

function trackOutgoing(app, cfg, chatId, result, direction) {
  if (!result || result.ok !== true || !result.result) return false;
  const mid = Number(result.result.message_id || 0);
  return trackTelegramMessage(app, chatId, mid, direction || "bot");
}

function markRetentionDeleted(app, record) {
  try {
    record.set("deleted", true);
    record.set("stamp", nowIso());
    app.save(record);
    return true;
  } catch (_) {
    return false;
  }
}

function deleteMessages(cfg, chatId, ids) {
  const clean = (Array.isArray(ids) ? ids : [])
    .map((id) => Math.floor(Number(id || 0)))
    .filter((id) => Number.isFinite(id) && id > 0)
    .slice(0, 100);
  if (!clean.length) return {ok: true};
  return telegramApi(cfg, "deleteMessages", {chat_id: String(chatId), message_ids: clean});
}

function deleteOne(cfg, chatId, id) {
  return telegramApi(cfg, "deleteMessage", {
    chat_id: String(chatId),
    message_id: Math.floor(Number(id || 0)),
  });
}

function cleanupRetentionRows(app, cfg, onlyChatId) {
  if (!app || !cfg || !cfg.ready) return {deleted: 0, attempted: 0};
  const filterChat = String(onlyChatId || "");
  const rows = store.rows(app, RETENTION_COLL, RETENTION_MAX_ROWS);
  const now = Date.now();
  const groups = {};

  for (const row of rows) {
    const payload = store.payloadOf(row);
    if (!payload || payload.preserve === true) continue;
    const chatId = String(payload.chatId || "");
    const messageId = Math.floor(Number(payload.messageId || 0));
    const due = Date.parse(String(payload.deleteAfter || ""));
    if (!chatId || !Number.isFinite(messageId) || messageId <= 0) continue;
    if (filterChat && chatId !== filterChat) continue;
    if (!Number.isFinite(due) || due > now) continue;
    if (!groups[chatId]) groups[chatId] = [];
    groups[chatId].push({row: row, messageId: messageId});
  }

  let deleted = 0;
  let attempted = 0;
  for (const chatId of Object.keys(groups)) {
    const items = groups[chatId];
    for (let offset = 0; offset < items.length; offset += 100) {
      const batch = items.slice(offset, offset + 100);
      attempted += batch.length;
      const bulk = deleteMessages(cfg, chatId, batch.map((item) => item.messageId));
      if (bulk.ok === true) {
        for (const item of batch) if (markRetentionDeleted(app, item.row)) deleted++;
        continue;
      }

      // One stale/unsupported Telegram message must not block the rest of the
      // batch. Retry individually; successful deletions are tombstoned while
      // transient failures stay queued for the next cleanup pass.
      for (const item of batch) {
        const single = deleteOne(cfg, chatId, item.messageId);
        if (single.ok === true && markRetentionDeleted(app, item.row)) deleted++;
      }
    }
  }
  return {deleted: deleted, attempted: attempted};
}

function cleanupChat(app, cfg, chatId) {
  return cleanupRetentionRows(app, cfg, String(chatId || ""));
}

function cleanupRetention(app) {
  const cfg = store.config();
  if (!cfg.ready) return {deleted: 0, attempted: 0};
  return cleanupRetentionRows(app, cfg, "");
}

function captureIncoming(e) {
  const cfg = store.config();
  if (!cfg.ready) return {captured: false};
  const secret = String(e.request.header.get("X-Telegram-Bot-Api-Secret-Token") || "");
  if (!secret || !$security.equal(secret, cfg.webhookSecret)) return {captured: false};

  const update = e.requestInfo().body || {};
  const message = update.message || null;
  const callback = update.callback_query || null;
  const chat = message && message.chat
    ? message.chat
    : (callback && callback.message && callback.message.chat ? callback.message.chat : null);
  if (!chat || String(chat.type || "") !== "private") return {captured: false};
  const chatId = String(chat.id || "");
  if (!activePrivateLink(e.app, chatId)) return {captured: false};

  // Opportunistic cleanup means a busy chat does not wait for cron.
  cleanupChat(e.app, cfg, chatId);
  if (!message) return {captured: false, cleaned: true};
  const mid = Number(message.message_id || 0);
  return {
    captured: trackTelegramMessage(e.app, chatId, mid, "user"),
    messageId: mid || null,
  };
}

function handle(e) {
  const cfg = store.config();
  if (!cfg.ready) return {handled: false};
  const secret = String(e.request.header.get("X-Telegram-Bot-Api-Secret-Token") || "");
  if (!secret || !$security.equal(secret, cfg.webhookSecret)) return {handled: false};
  const update = e.requestInfo().body || {};
  const message = update.message || null;
  if (!message || String(message.chat && message.chat.type || "") !== "private") return {handled: false};
  const command = tg.parseCommand(message.text || "", cfg.botUsername);
  if (command.name !== "test") return {handled: false};

  const telegramUserId = String(message.from && message.from.id || "");
  const chatId = String(message.chat && message.chat.id || "");
  const link = store.linkByTelegram(e.app, telegramUserId);
  if (!link) {
    telegramApi(cfg, "sendMessage", {
      chat_id: chatId,
      text: "Сначала подключите Telegram в WesiOS: Профиль → Telegram.",
    });
    return {handled: true};
  }
  const identity = store.resolveIdentityForAuth(e.app, link.payload.authUserId);
  if (!identity) {
    store.revokeByAuth(e.app, link.payload.authUserId, "identity-invalid");
    return {handled: true};
  }
  const selected = store.selectVisibleOrganization(e.app, identity, link.payload.activeOrganizationId);
  if (!selected.id) return {handled: true};

  const result = telegramApi(cfg, "sendPhoto", {
    chat_id: chatId,
    photo: `${cfg.publicBaseUrl}/telegram/visuals/push.jpg`,
    caption: [
      "<b>WesiOS · Test Push</b>",
      "Канал уведомлений работает.",
      "Risk и overdue алерты приходят сюда с сервера, даже когда приложение WesiOS закрыто.",
    ].join("\n"),
    parse_mode: "HTML",
    protect_content: true,
    reply_markup: {
      inline_keyboard: [[{
        text: "Открыть WesiOS",
        url: `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=home&org=${encodeURIComponent(selected.id)}`,
      }]],
    },
  });
  trackOutgoing(e.app, cfg, chatId, result, "bot");
  if (result.ok && result.result && result.result.message_id) {
    link.payload.lastBotMessageId = Math.max(
      Number(link.payload.lastBotMessageId || 0),
      Number(result.result.message_id || 0),
    );
    link.payload.lastTelegramMessageId = Math.max(
      Number(link.payload.lastTelegramMessageId || 0),
      Number(result.result.message_id || 0),
    );
    store.updateLink(e.app, link.payload);
  }
  return {handled: true};
}

module.exports = {
  RETENTION_COLL,
  RETENTION_TTL_MS,
  retentionRid,
  retentionDueAt,
  trackTelegramMessage,
  trackOutgoing,
  captureIncoming,
  cleanupChat,
  cleanupRetention,
  handle,
};
'''
Path("server/pb_hooks/wesi_telegram_interactions.js").write_text(interactions, encoding="utf-8")

replace_once(
    "server/pb_hooks/wesi_telegram_gateway.js",
    'const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");\n',
    'const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");\nconst interactions = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_interactions.js");\n',
)
replace_once(
    "server/pb_hooks/wesi_telegram_gateway.js",
    '''function sendMessage(cfg, chatId, text, keyboard) {\n  const payload = {\n    chat_id: chatId,\n    text: String(text || "").slice(0, 4096),\n    parse_mode: "HTML",\n    disable_web_page_preview: true,\n  };\n  if (keyboard && keyboard.length) payload.reply_markup = {inline_keyboard: keyboard};\n  return telegramApi(cfg, "sendMessage", payload);\n}\n''',
    '''function sendMessage(cfg, chatId, text, keyboard) {\n  const payload = {\n    chat_id: chatId,\n    text: String(text || "").slice(0, 4096),\n    parse_mode: "HTML",\n    disable_web_page_preview: true,\n  };\n  if (keyboard && keyboard.length) payload.reply_markup = {inline_keyboard: keyboard};\n  const result = telegramApi(cfg, "sendMessage", payload);\n  try {\n    interactions.trackOutgoing(\n      typeof $app !== "undefined" ? $app : null,\n      cfg,\n      chatId,\n      result,\n      "bot",\n    );\n  } catch (_) {}\n  return result;\n}\n''',
)

replace_once(
    "server/pb_hooks/wesi_telegram_experience.js",
    'const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");\n',
    'const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");\nconst interactions = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_interactions.js");\n',
)
replace_once(
    "server/pb_hooks/wesi_telegram_experience.js",
    '''function sendPhoto(cfg, chatId, kind, caption, keyboard) {\n  const body = {\n    chat_id: chatId,\n    photo: visualUrl(cfg, kind),\n    caption: String(caption || "").slice(0, 1024),\n    parse_mode: "HTML",\n    protect_content: true,\n  };\n  const markup = inlineKeyboard(keyboard);\n  if (markup) body.reply_markup = markup;\n  return telegramApi(cfg, "sendPhoto", body);\n}\n''',
    '''function sendPhoto(cfg, chatId, kind, caption, keyboard) {\n  const body = {\n    chat_id: chatId,\n    photo: visualUrl(cfg, kind),\n    caption: String(caption || "").slice(0, 1024),\n    parse_mode: "HTML",\n    protect_content: true,\n  };\n  const markup = inlineKeyboard(keyboard);\n  if (markup) body.reply_markup = markup;\n  const result = telegramApi(cfg, "sendPhoto", body);\n  try {\n    interactions.trackOutgoing(\n      typeof $app !== "undefined" ? $app : null,\n      cfg,\n      chatId,\n      result,\n      "bot",\n    );\n  } catch (_) {}\n  return result;\n}\n''',
)

replace_once(
    "server/pb_hooks/wesi_telegram.pb.js",
    '''routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {\n  // Experience preprocessing records private message ids, adds contextual\n''',
    '''routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {\n  // Capture the exact incoming message id and opportunistically remove any\n  // WesiOS chat messages whose 24-hour retention window has expired.\n  try {\n    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);\n    interactions.captureIncoming(e);\n  } catch (_) {}\n\n  // Experience preprocessing records private message ids, adds contextual\n''',
)
replace_once(
    "server/pb_hooks/wesi_telegram.pb.js",
    '''cronAdd("wesios_telegram_alerts_v2", "*/5 * * * *", () => {\n  try {\n    const experience = require(`${__hooks}/wesi_telegram_experience.js`);\n    experience.runNotifier($app);\n  } catch (_) {}\n});\n''',
    '''cronAdd("wesios_telegram_alerts_v2", "*/5 * * * *", () => {\n  try {\n    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);\n    interactions.cleanupRetention($app);\n  } catch (_) {}\n  try {\n    const experience = require(`${__hooks}/wesi_telegram_experience.js`);\n    experience.runNotifier($app);\n  } catch (_) {}\n});\n''',
)

retention_test = r'''import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const retention = require("./wesi_telegram_interactions.js");

assert.equal(retention.RETENTION_TTL_MS, 24 * 60 * 60 * 1000);
assert.equal(retention.RETENTION_COLL, "telegram_retention");
assert.equal(retention.retentionRid("123", 456), "msg:123:456");
assert.equal(
  retention.retentionDueAt("2026-08-18T10:00:00.000Z"),
  "2026-08-19T10:00:00.000Z",
);
console.log("TELEGRAM_RETENTION_24H_OK");
'''
Path("server/pb_hooks/wesi_telegram_retention_test.mjs").write_text(retention_test, encoding="utf-8")

replace_once(
    ".github/workflows/telegram-gate.yml",
    '''      - name: Run Telegram unit tests\n        run: node server/pb_hooks/wesi_telegram_lib_test.mjs\n''',
    '''      - name: Run Telegram unit tests\n        run: |\n          node server/pb_hooks/wesi_telegram_lib_test.mjs\n          node server/pb_hooks/wesi_telegram_retention_test.mjs\n''',
)

print("TELEGRAM_RETENTION_PATCH_APPLIED")
