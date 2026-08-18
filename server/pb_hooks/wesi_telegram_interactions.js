const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");

function telegramApi(cfg, method, payload) {
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
    return {ok: false};
  }
  const data = response && response.json && typeof response.json === "object" ? response.json : {};
  return {
    ok: !!response && response.statusCode >= 200 && response.statusCode < 300 && data.ok === true,
    result: data.result || null,
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

module.exports = {handle};
