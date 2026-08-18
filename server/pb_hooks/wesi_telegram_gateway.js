const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");
const interactions = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_interactions.js");
const financeTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_finance_tools.js");
const horizonTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_horizon_tools.js");
const taskTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_task_tools.js");

const RATE_LIMIT = 24;
const RATE_WINDOW_MS = 60 * 1000;

function requestIdentity(e) {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ctx.authUserId = String(e.auth && e.auth.id || "");
  return ctx;
}

function visibleSelection(app, identity, requested) {
  const wanted = String(requested || "").trim();
  const selected = store.selectVisibleOrganization(app, identity, wanted);
  if (wanted && selected.id !== wanted) {
    return {
      ok: false,
      code: "FORBIDDEN",
      message: "Нет доступа к этой организации",
      organizations: selected.organizations,
    };
  }
  if (!selected.id) {
    return {
      ok: false,
      code: "FORBIDDEN",
      message: "Нет доступной организации",
      organizations: selected.organizations,
    };
  }
  return {ok: true, id: selected.id, organizations: selected.organizations};
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
      timeout: 12,
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

function sendTyping(cfg, chatId) {
  telegramApi(cfg, "sendChatAction", {chat_id: chatId, action: "typing"});
}

function sendMessage(cfg, chatId, text, keyboard) {
  const payload = {
    chat_id: chatId,
    text: String(text || "").slice(0, 4096),
    parse_mode: "HTML",
    disable_web_page_preview: true,
  };
  if (keyboard && keyboard.length) payload.reply_markup = {inline_keyboard: keyboard};
  const result = telegramApi(cfg, "sendMessage", payload);
  try {
    interactions.trackOutgoing(
      typeof $app !== "undefined" ? $app : null,
      cfg,
      chatId,
      result,
      "bot",
    );
  } catch (_) {}
  return result;
}

function answerCallback(cfg, callbackId, text) {
  if (!callbackId) return;
  telegramApi(cfg, "answerCallbackQuery", {
    callback_query_id: callbackId,
    text: String(text || "").slice(0, 180),
    show_alert: false,
  });
}

function deepLinkUrl(cfg, target, organizationId) {
  const route = String(target || "home").replace(/[^a-z0-9_-]/gi, "").slice(0, 24) || "home";
  const org = encodeURIComponent(String(organizationId || ""));
  return `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=${encodeURIComponent(route)}&org=${org}`;
}

function mainKeyboard(cfg, organizationId) {
  return [
    [
      {text: "Подробнее", callback_data: tg.callback("brief", "")},
      {text: "Риск", callback_data: tg.callback("risk", "")},
    ],
    [
      {text: "Задачи", callback_data: tg.callback("today", "")},
      {text: "Сменить org", callback_data: tg.callback("orgs", "")},
    ],
    [{text: "Открыть WesiOS", url: deepLinkUrl(cfg, "home", organizationId)}],
  ];
}

function taskKeyboard(cfg, organizationId) {
  return [
    [
      {text: "Сегодня", callback_data: tg.callback("today", "")},
      {text: "Просрочки", callback_data: tg.callback("overdue", "")},
    ],
    [{text: "Открыть задачи", url: deepLinkUrl(cfg, "tasks", organizationId)}],
  ];
}

function orgKeyboard(organizations, activeId) {
  const buttons = [];
  const source = Array.isArray(organizations) ? organizations.slice(0, 18) : [];
  for (const org of source) {
    const label = (String(org.id || "") === String(activeId || "") ? "✓ " : "") +
      String(org.name || org.id || "org");
    buttons.push([
      {
        text: label.slice(0, 52),
        callback_data: tg.callback("org", String(org.id || "")),
      },
    ]);
  }
  return buttons;
}

function safeToolCall(fn) {
  try {
    return fn();
  } catch (_) {
    return {
      ok: false,
      code: "DATA_UNAVAILABLE",
      message: "Данные WesiOS временно недоступны",
    };
  }
}

function financeBalance(e, ctx, organizationId) {
  return safeToolCall(() =>
    financeTools.execute(e, ctx, "finance_balance", {}, organizationId));
}

function horizonSnapshot(e, ctx, organizationId) {
  return safeToolCall(() =>
    horizonTools.execute(e, ctx, "horizon_snapshot", {}, organizationId));
}

function timezoneOffset(payload) {
  const prefs = payload && payload.notificationPrefs &&
      typeof payload.notificationPrefs === "object"
    ? payload.notificationPrefs
    : {};
  return Math.max(
    -840,
    Math.min(
      840,
      Number(prefs.timezoneOffsetMinutes == null
        ? (payload && payload.timezoneOffsetMinutes || 0)
        : prefs.timezoneOffsetMinutes),
    ),
  );
}

function dueTasks(e, ctx, organizationId, mode, limit, offsetMinutes) {
  return safeToolCall(() => taskTools.execute(
    e,
    ctx,
    "tasks_list",
    {
      dueMode: mode,
      timezoneOffsetMinutes: Math.max(-840, Math.min(840, Number(offsetMinutes || 0))),
      limit: Math.max(1, Math.min(100, Number(limit || 8))),
    },
    organizationId,
  ));
}

function orgName(app, identity, organizationId) {
  const organizations = store.visibleOrganizations(app, identity);
  const hit = organizations.find((item) =>
    String(item.id || "") === String(organizationId || ""));
  return hit ? String(hit.name || hit.id) : String(organizationId || "Организация");
}

function inferOrganization(organizations, raw) {
  const input = String(raw || "").toLowerCase();
  if (!input || !Array.isArray(organizations)) return "";
  const hits = [];
  for (const org of organizations) {
    const id = String(org.id || "");
    const name = String(org.name || "").trim().toLowerCase();
    if (!id || !name) continue;
    let matched = input.indexOf(name) >= 0 || input.indexOf(id.toLowerCase()) >= 0;
    if (!matched) {
      const tokens = name.split(/[^a-zа-яё0-9]+/i)
        .filter((token) => token.length >= 4 && token !== "wesi");
      matched = tokens.some((token) => input.indexOf(token) >= 0);
    }
    if (matched) hits.push(id);
  }
  const unique = Array.from(new Set(hits));
  return unique.length === 1 ? unique[0] : "";
}

function renderTaskList(title, result, organization, maxItems) {
  if (!result || result.ok !== true) {
    const message = result && result.code === "FORBIDDEN"
      ? "Нет доступа к задачам этой организации."
      : "Задачи сейчас недоступны.";
    return `<b>${tg.escapeHtml(title)}</b>\n${message}`;
  }
  const data = result.result || {};
  const tasks = Array.isArray(data.tasks) ? data.tasks : [];
  const total = Number(data.totalCount == null ? tasks.length : data.totalCount);
  const lines = [
    `<b>${tg.escapeHtml(title)}</b> · ${tg.escapeHtml(organization)}`,
    `Всего: <b>${Number.isFinite(total) ? total : tasks.length}</b>`,
  ];
  if (!tasks.length) {
    lines.push("Ничего нет.");
    return lines.join("\n");
  }
  for (const item of tasks.slice(0, Math.max(1, Number(maxItems || 6)))) {
    const marker = String(item.priority || "") === "urgent" ? "!" : "•";
    lines.push(`${marker} ${tg.escapeHtml(String(item.title || "Без названия").slice(0, 160))}`);
  }
  if (Number.isFinite(total) && total > tasks.length) lines.push(`…ещё ${total - tasks.length}`);
  return lines.join("\n");
}

function renderCash(result) {
  if (!result || result.ok !== true) {
    if (result && result.code === "FORBIDDEN") {
      return "Нет доступа к финансам этой организации.";
    }
    return "Касса сейчас недоступна — WesiOS не подставляет ноль вместо ошибки.";
  }
  const data = result.result || {};
  return [
    `<b>${tg.escapeHtml(data.organizationName || "Касса")}</b> · сейчас`,
    `Касса: <b>${tg.escapeHtml(tg.formatMoney(data.currentBalance, data.reportingCurrency))}</b>`,
  ].join("\n");
}

function renderRisk(result) {
  if (!result || result.ok !== true) {
    if (result && result.code === "FORBIDDEN") {
      return "Нет доступа к Horizon этой организации.";
    }
    return "Риск сейчас недоступен: сервер не получил надёжный ledger snapshot.";
  }
  const data = result.result || {};
  const risk = tg.riskFromCushionDays(data.cushionDays);
  const cushion = data.cushionDays == null ? "—" : `${data.cushionDays} дн.`;
  return [
    `<b>${tg.escapeHtml(data.organizationName || "Horizon")}</b> · риск`,
    `Уровень: <b>${tg.escapeHtml(risk.label)}</b>`,
    `Запас по текущему темпу: <b>${tg.escapeHtml(cushion)}</b>`,
    `Касса: ${tg.escapeHtml(tg.formatMoney(data.currentBalance, data.reportingCurrency))}`,
    "<i>Серверный ledger-runway; бот не выдумывает вероятность разрыва.</i>",
  ].join("\n");
}

function brief(e, ctx, app, organizationId, offsetMinutes) {
  const finance = financeBalance(e, ctx, organizationId);
  const horizon = horizonSnapshot(e, ctx, organizationId);
  const today = dueTasks(e, ctx, organizationId, "today", 3, offsetMinutes);
  const overdue = dueTasks(e, ctx, organizationId, "overdue", 3, offsetMinutes);
  const name = orgName(app, ctx, organizationId);

  const lines = [`<b>${tg.escapeHtml(name)}</b> · сейчас`];
  if (finance.ok === true) {
    lines.push(
      `Касса: <b>${tg.escapeHtml(tg.formatMoney(finance.result.currentBalance, finance.result.reportingCurrency))}</b>`,
    );
  } else {
    lines.push(finance.code === "FORBIDDEN" ? "Касса: нет доступа" : "Касса: данные недоступны");
  }
  if (horizon.ok === true) {
    const risk = tg.riskFromCushionDays(horizon.result.cushionDays);
    const days = horizon.result.cushionDays == null
      ? "—"
      : `${horizon.result.cushionDays} дн.`;
    lines.push(`Риск: <b>${tg.escapeHtml(risk.label)}</b> · запас ${tg.escapeHtml(days)}`);
  } else {
    lines.push(horizon.code === "FORBIDDEN"
      ? "Риск: нет доступа к Horizon"
      : "Риск: данные недоступны");
  }
  if (today.ok === true) {
    lines.push(`Задач сегодня: <b>${Number(today.result.totalCount || 0)}</b>`);
  } else {
    lines.push(today.code === "FORBIDDEN" ? "Задачи: нет доступа" : "Задачи: данные недоступны");
  }
  if (overdue.ok === true) {
    lines.push(`Просрочено: <b>${Number(overdue.result.totalCount || 0)}</b>`);
  }
  return lines.join("\n");
}

function helpText(linked) {
  if (!linked) {
    return [
      "<b>Wesi Telegram</b>",
      "Привяжите аккаунт в WesiOS: Профиль → Telegram.",
      "Без привязки финансовые и рабочие данные недоступны.",
    ].join("\n");
  }
  return [
    "<b>Wesi Telegram</b>",
    "/brief — короткая сводка",
    "/cash — текущая касса",
    "/risk — серверный риск/runway",
    "/today — задачи на сегодня",
    "/overdue — просрочки",
    "/org — сменить организацию",
    "Можно и обычным текстом: «сколько денег на Beats?»",
  ].join("\n");
}

function liveLink(app, telegramUserId) {
  const stored = store.linkByTelegram(app, telegramUserId);
  if (!stored) return {ok: false, code: "NOT_LINKED"};
  const identity = store.resolveIdentityForAuth(app, stored.payload.authUserId);
  if (!identity) {
    store.revokeByAuth(app, stored.payload.authUserId, "identity-invalid");
    return {ok: false, code: "NOT_LINKED"};
  }
  const selected = store.selectVisibleOrganization(
    app,
    identity,
    stored.payload.activeOrganizationId,
  );
  if (!selected.id) return {ok: false, code: "FORBIDDEN"};
  if (selected.id !== stored.payload.activeOrganizationId) {
    stored.payload.activeOrganizationId = selected.id;
    store.updateLink(app, stored.payload);
  }
  return {
    ok: true,
    stored: stored,
    identity: identity,
    organizationId: selected.id,
    organizations: selected.organizations,
  };
}

function acceptUserRate(app, live) {
  const rate = tg.acceptRate(
    live.stored.payload.rateLimit,
    Date.now(),
    RATE_LIMIT,
    RATE_WINDOW_MS,
  );
  live.stored.payload.rateLimit = rate.state;
  store.updateLink(app, live.stored.payload);
  return rate.ok;
}

function handleCommand(e, cfg, live, chatId, command) {
  const name = String(command.name || "").toLowerCase();
  const inferred = command.raw && String(command.raw).charAt(0) !== "/"
    ? inferOrganization(live.organizations, command.raw)
    : "";
  const organizationId = inferred || live.organizationId;
  const offset = timezoneOffset(live.stored.payload);

  if (["brief", "cash", "risk", "today", "overdue"].indexOf(name) >= 0) {
    sendTyping(cfg, chatId);
  }

  if (name === "brief") {
    return sendMessage(
      cfg,
      chatId,
      brief(e, live.identity, e.app, organizationId, offset),
      mainKeyboard(cfg, organizationId),
    );
  }
  if (name === "cash") {
    return sendMessage(
      cfg,
      chatId,
      renderCash(financeBalance(e, live.identity, organizationId)),
      [
        [
          {text: "Сменить org", callback_data: tg.callback("orgs", "")},
          {text: "Риск", callback_data: tg.callback("risk", "")},
        ],
        [{text: "Открыть кассу", url: deepLinkUrl(cfg, "treasury", organizationId)}],
      ],
    );
  }
  if (name === "risk") {
    return sendMessage(
      cfg,
      chatId,
      renderRisk(horizonSnapshot(e, live.identity, organizationId)),
      [
        [
          {text: "Касса", callback_data: tg.callback("cash", "")},
          {text: "Сменить org", callback_data: tg.callback("orgs", "")},
        ],
        [{text: "Открыть Horizon", url: deepLinkUrl(cfg, "forecast", organizationId)}],
      ],
    );
  }
  if (name === "today" || name === "overdue") {
    const result = dueTasks(e, live.identity, organizationId, name, 8, offset);
    const title = name === "today" ? "Задачи на сегодня" : "Просроченные задачи";
    return sendMessage(
      cfg,
      chatId,
      renderTaskList(title, result, orgName(e.app, live.identity, organizationId), 8),
      taskKeyboard(cfg, organizationId),
    );
  }
  if (name === "org" || name === "orgs") {
    const query = String(command.args || "").trim();
    if (query) {
      const selected = store.selectVisibleOrganization(e.app, live.identity, query);
      const exact = selected.organizations.some((item) =>
        item.id === selected.id &&
        (item.id.toLowerCase() === query.toLowerCase() ||
          item.name.toLowerCase() === query.toLowerCase()));
      const partial = selected.organizations.filter((item) =>
        item.name.toLowerCase().indexOf(query.toLowerCase()) >= 0);
      if (selected.id && (exact || partial.length === 1)) {
        live.stored.payload.activeOrganizationId = selected.id;
        store.updateLink(e.app, live.stored.payload);
        return sendMessage(
          cfg,
          chatId,
          `Текущая организация: <b>${tg.escapeHtml(orgName(e.app, live.identity, selected.id))}</b>`,
          mainKeyboard(cfg, selected.id),
        );
      }
    }
    return sendMessage(
      cfg,
      chatId,
      "Выберите организацию. Бот покажет только те, к которым у вас есть доступ.",
      orgKeyboard(live.organizations, live.organizationId),
    );
  }
  if (name === "help" || name === "start") {
    return sendMessage(cfg, chatId, helpText(true), mainKeyboard(cfg, live.organizationId));
  }
  return sendMessage(
    cfg,
    chatId,
    "Не понял команду. Используйте /brief, /cash, /risk, /today, /overdue или /org.",
    mainKeyboard(cfg, live.organizationId),
  );
}

function handleStartLink(e, cfg, message, command) {
  const code = tg.parseStartCode(command);
  const chat = message && message.chat || {};
  const from = message && message.from || {};
  const chatId = String(chat.id || "");
  const telegramUserId = String(from.id || "");
  if (!code) return sendMessage(cfg, chatId, helpText(false));

  const consumed = store.consumeLinkCode(e.app, code);
  if (!consumed.ok) {
    const expired = consumed.code === "LINK_CODE_EXPIRED";
    return sendMessage(
      cfg,
      chatId,
      expired
        ? "Код привязки истёк. Создайте новый в WesiOS."
        : "Код привязки недействителен. Создайте новый в WesiOS.",
    );
  }
  const identity = store.resolveIdentityForAuth(e.app, consumed.payload.authUserId);
  if (!identity) {
    return sendMessage(
      cfg,
      chatId,
      "Аккаунт WesiOS больше недоступен. Войдите в приложение и создайте новую привязку.",
    );
  }

  const alreadyTg = store.linkByTelegram(e.app, telegramUserId);
  if (alreadyTg && String(alreadyTg.payload.authUserId || "") !== String(identity.authUserId || "")) {
    return sendMessage(
      cfg,
      chatId,
      "Этот Telegram уже привязан к другому аккаунту WesiOS. Сначала отвяжите его там.",
    );
  }
  const alreadyAuth = store.linkByAuth(e.app, identity.authUserId);
  if (alreadyAuth && String(alreadyAuth.payload.telegramUserId || "") !== telegramUserId) {
    return sendMessage(
      cfg,
      chatId,
      "Аккаунт WesiOS уже привязан к другому Telegram. Отзовите старую привязку в приложении.",
    );
  }

  const selected = visibleSelection(
    e.app,
    identity,
    consumed.payload.activeOrganizationId,
  );
  if (!selected.ok) {
    return sendMessage(
      cfg,
      chatId,
      "Привязка не завершена: у аккаунта нет доступа к выбранной организации.",
    );
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
    timezoneOffsetMinutes: Number(consumed.payload.timezoneOffsetMinutes || 0),
  });
  return sendMessage(
    cfg,
    chatId,
    [
      "<b>WesiOS подключён.</b>",
      `Организация: <b>${tg.escapeHtml(orgName(e.app, identity, saved.activeOrganizationId))}</b>`,
      "Права берутся из WesiOS при каждом запросе. Отвязка в приложении блокирует бот сразу.",
    ].join("\n"),
    mainKeyboard(cfg, saved.activeOrganizationId),
  );
}

function handlePrivateMessage(e, cfg, message) {
  const from = message && message.from || {};
  const chat = message && message.chat || {};
  const chatId = String(chat.id || "");
  const telegramUserId = String(from.id || "");
  if (!chatId || !telegramUserId) return;
  const command = tg.parseCommand(message.text || "", cfg.botUsername);
  if (command.name === "foreign" || !command.name) return;
  if (command.name === "start") {
    const code = tg.parseStartCode(command);
    if (code) return handleStartLink(e, cfg, message, command);
  }

  const live = liveLink(e.app, telegramUserId);
  if (!live.ok) return sendMessage(cfg, chatId, helpText(false));
  if (!acceptUserRate(e.app, live)) {
    return sendMessage(cfg, chatId, "Слишком много команд подряд. Подождите минуту.");
  }
  return handleCommand(e, cfg, live, chatId, command);
}

function handleGroupMessage(e, cfg, message) {
  if (!tg.isExplicitGroupCommand(message && message.text || "", cfg.botUsername)) {
    return;
  }
  const command = tg.parseCommand(message && message.text || "", cfg.botUsername);
  if (command.name === "foreign" || !command.name) return;
  const chatId = String(message && message.chat && message.chat.id || "");
  if (!chatId) return;
  // MVP groups are deliberately fail-closed. Even an explicit mention never
  // renders balances or task titles until a dedicated group policy exists.
  return sendMessage(
    cfg,
    chatId,
    `Чувствительные данные WesiOS доступны только в личке с @${tg.escapeHtml(cfg.botUsername)}.`,
  );
}

function handleCallback(e, cfg, query) {
  const from = query && query.from || {};
  const message = query && query.message || {};
  const chatId = String(message && message.chat && message.chat.id || "");
  const telegramUserId = String(from.id || "");
  const parsed = tg.parseCallback(query && query.data || "");
  if (!chatId || !telegramUserId || !parsed) {
    return answerCallback(cfg, query && query.id, "Кнопка устарела");
  }
  const live = liveLink(e.app, telegramUserId);
  if (!live.ok) {
    answerCallback(cfg, query.id, "Привязка WesiOS недействительна");
    return sendMessage(cfg, chatId, helpText(false));
  }
  if (!acceptUserRate(e.app, live)) {
    return answerCallback(cfg, query.id, "Слишком много запросов");
  }

  if (parsed.action === "org") {
    const selected = visibleSelection(e.app, live.identity, parsed.value);
    if (!selected.ok) {
      return answerCallback(cfg, query.id, "Нет доступа к этой организации");
    }
    live.stored.payload.activeOrganizationId = selected.id;
    store.updateLink(e.app, live.stored.payload);
    answerCallback(cfg, query.id, "Организация изменена");
    return sendMessage(
      cfg,
      chatId,
      `Текущая организация: <b>${tg.escapeHtml(orgName(e.app, live.identity, selected.id))}</b>`,
      mainKeyboard(cfg, selected.id),
    );
  }
  answerCallback(cfg, query.id, "Готово");
  return handleCommand(e, cfg, live, chatId, {
    name: parsed.action,
    args: parsed.value,
    raw: "",
  });
}

function alertStateOf(payload) {
  return payload && payload.alertState && typeof payload.alertState === "object"
    ? payload.alertState
    : {};
}

function runNotifier(app) {
  const cfg = store.config();
  if (!cfg.ready) return;
  const links = store.rows(app, store.COLL_LINKS, 5000);
  for (const row of links) {
    const payload = store.payloadOf(row);
    if (!payload || payload.revokedAt || !payload.telegramUserId ||
        !payload.telegramChatId || !payload.authUserId) {
      continue;
    }
    const identity = store.resolveIdentityForAuth(app, payload.authUserId);
    if (!identity) {
      store.revokeByAuth(app, payload.authUserId, "identity-invalid");
      continue;
    }
    const selected = store.selectVisibleOrganization(app, identity, payload.activeOrganizationId);
    if (!selected.id) continue;
    if (selected.id !== payload.activeOrganizationId) payload.activeOrganizationId = selected.id;

    const prefs = payload.notificationPrefs && typeof payload.notificationPrefs === "object"
      ? payload.notificationPrefs
      : {};
    const offset = timezoneOffset(payload);
    const state = alertStateOf(payload);
    const event = {app: app};

    const riskResult = horizonSnapshot(event, identity, selected.id);
    if (riskResult.ok === true) {
      const risk = tg.riskFromCushionDays(riskResult.result.cushionDays);
      if (prefs.risk === false) {
        state.riskLevel = risk.level;
      } else if (!tg.isQuietHours(
        Date.now(),
        offset,
        prefs.quietFromHour,
        prefs.quietToHour,
      )) {
        if (tg.shouldNotifyRisk(state.riskLevel, risk.level)) {
          sendMessage(
            cfg,
            payload.telegramChatId,
            [
              `<b>WesiOS · ${tg.escapeHtml(riskResult.result.organizationName || selected.id)}</b>`,
              `Кассовый риск: <b>${tg.escapeHtml(risk.label)}</b>`,
              `Запас по текущему темпу: <b>${riskResult.result.cushionDays == null ? "—" : tg.escapeHtml(String(riskResult.result.cushionDays) + " дн.")}</b>`,
            ].join("\n"),
            [[{text: "Открыть риск", callback_data: tg.callback("risk", "")}]],
          );
        }
        state.riskLevel = risk.level;
      }
    }

    const overdue = dueTasks(event, identity, selected.id, "overdue", 5, offset);
    if (overdue.ok === true) {
      const count = Math.max(0, Number(overdue.result.totalCount || 0));
      if (prefs.overdue === false) {
        state.overdueCount = count;
      } else if (!tg.isQuietHours(
        Date.now(),
        offset,
        prefs.quietFromHour,
        prefs.quietToHour,
      )) {
        if (tg.shouldNotifyOverdue(state.overdueCount, count)) {
          sendMessage(
            cfg,
            payload.telegramChatId,
            renderTaskList(
              "Просроченные задачи",
              overdue,
              orgName(app, identity, selected.id),
              5,
            ),
            taskKeyboard(cfg, selected.id),
          );
        }
        state.overdueCount = count;
      }
    }

    payload.alertState = state;
    payload.lastNotifierAt = new Date().toISOString();
    store.updateLink(app, payload);
  }
}

function createLink(e) {
  const cfg = store.config();
  if (!cfg.ready) return e.json(503, {ok: false, code: "TELEGRAM_NOT_CONFIGURED"});
  const identity = requestIdentity(e);
  const current = store.linkByAuth(e.app, identity.authUserId);
  if (current) return e.json(409, {ok: false, code: "TELEGRAM_ALREADY_LINKED"});
  const body = e.requestInfo().body || {};
  const selected = visibleSelection(e.app, identity, body.activeOrganizationId);
  if (!selected.ok) {
    return e.json(403, {ok: false, code: selected.code, message: selected.message});
  }
  const ticket = store.createLinkCode(
    e.app,
    identity,
    selected.id,
    body.timezoneOffsetMinutes,
  );
  return e.json(200, {
    ok: true,
    linked: false,
    code: ticket.code,
    expiresAt: ticket.payload.expiresAt,
    botUsername: cfg.botUsername,
    deepLink: `https://t.me/${cfg.botUsername}?start=${encodeURIComponent(ticket.code)}`,
    activeOrganizationId: selected.id,
  });
}

function status(e) {
  const identity = requestIdentity(e);
  const current = store.linkByAuth(e.app, identity.authUserId);
  if (!current) return e.json(200, {ok: true, linked: false});
  const selected = store.selectVisibleOrganization(
    e.app,
    identity,
    current.payload.activeOrganizationId,
  );
  if (!selected.id) {
    store.revokeByAuth(e.app, identity.authUserId, "no-visible-org");
    return e.json(200, {ok: true, linked: false});
  }
  return e.json(200, {
    ok: true,
    linked: true,
    telegramUsername: String(current.payload.telegramUsername || ""),
    telegramFirstName: String(current.payload.telegramFirstName || ""),
    linkedAt: current.payload.linkedAt || null,
    activeOrganizationId: selected.id,
    activeOrganizationName: orgName(e.app, identity, selected.id),
    notificationPrefs: current.payload.notificationPrefs || {},
  });
}

function revoke(e) {
  const identity = requestIdentity(e);
  store.revokeByAuth(e.app, identity.authUserId, "app");
  return e.json(200, {ok: true, linked: false});
}

function context(e) {
  const identity = requestIdentity(e);
  const current = store.linkByAuth(e.app, identity.authUserId);
  if (!current) return e.json(404, {ok: false, code: "TELEGRAM_NOT_LINKED"});
  const body = e.requestInfo().body || {};
  const selected = visibleSelection(e.app, identity, body.activeOrganizationId);
  if (!selected.ok) {
    return e.json(403, {ok: false, code: selected.code, message: selected.message});
  }
  current.payload.activeOrganizationId = selected.id;
  store.updateLink(e.app, current.payload);
  return e.json(200, {
    ok: true,
    activeOrganizationId: selected.id,
    activeOrganizationName: orgName(e.app, identity, selected.id),
  });
}

function preferences(e) {
  const identity = requestIdentity(e);
  const current = store.linkByAuth(e.app, identity.authUserId);
  if (!current) return e.json(404, {ok: false, code: "TELEGRAM_NOT_LINKED"});
  const body = e.requestInfo().body || {};
  const previous = current.payload.notificationPrefs &&
      typeof current.payload.notificationPrefs === "object"
    ? current.payload.notificationPrefs
    : {};
  const next = Object.assign({}, previous);
  if (body.risk != null) next.risk = body.risk === true;
  if (body.overdue != null) next.overdue = body.overdue === true;
  if (body.quietFromHour != null) {
    next.quietFromHour = Math.max(0, Math.min(23, Number(body.quietFromHour)));
  }
  if (body.quietToHour != null) {
    next.quietToHour = Math.max(0, Math.min(23, Number(body.quietToHour)));
  }
  if (body.timezoneOffsetMinutes != null) {
    next.timezoneOffsetMinutes = Math.max(
      -840,
      Math.min(840, Number(body.timezoneOffsetMinutes)),
    );
  }
  current.payload.notificationPrefs = next;
  store.updateLink(e.app, current.payload);
  return e.json(200, {ok: true, notificationPrefs: next});
}

function open(e) {
  const query = e.requestInfo().query || {};
  const target = String(query.target || "home").toLowerCase();
  const org = String(query.org || "")
    .replace(/[^A-Za-z0-9_.:-]/g, "")
    .slice(0, 80);
  const allowed = {
    home: "home",
    treasury: "treasury",
    forecast: "treasury/forecast",
    tasks: "tasks",
    ai: "ai",
  };
  const route = allowed[target] || "home";
  const suffix = org ? `?organizationId=${encodeURIComponent(org)}` : "";
  return e.redirect(302, `wesios:///${route}${suffix}`);
}

function webhook(e) {
  const cfg = store.config();
  if (!cfg.ready) return e.json(503, {ok: false, code: "TELEGRAM_NOT_CONFIGURED"});
  const secret = String(e.request.header.get("X-Telegram-Bot-Api-Secret-Token") || "");
  if (!secret || !$security.equal(secret, cfg.webhookSecret)) {
    return e.json(401, {ok: false, code: "UNAUTHORIZED"});
  }
  const update = e.requestInfo().body || {};
  try {
    if (update.callback_query) {
      handleCallback(e, cfg, update.callback_query);
    } else if (update.message) {
      const type = String(update.message.chat && update.message.chat.type || "");
      if (type === "private") handlePrivateMessage(e, cfg, update.message);
      else handleGroupMessage(e, cfg, update.message);
    }
  } catch (_) {
    // Telegram retries any non-2xx update. The user-facing command handlers
    // already distinguish data/auth failures; unexpected failures are logged
    // by PocketBase but the update is acknowledged to prevent a retry storm.
  }
  return e.json(200, {ok: true});
}

module.exports = {
  createLink,
  status,
  revoke,
  context,
  preferences,
  open,
  webhook,
  runNotifier,
};
