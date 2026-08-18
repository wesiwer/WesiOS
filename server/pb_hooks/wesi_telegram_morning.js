const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");
const interactions = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_interactions.js");
const taskTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_task_tools.js");

const DAY_MS = 24 * 60 * 60 * 1000;
const ANCHOR_DAY = Math.floor(Date.UTC(2026, 7, 18) / DAY_MS); // 18 Aug 2026 = Nirvana.
const MORNING_HOUR = 8;
const MAX_THREAD_CHARS = 850;
const MIN_THREAD_CHARS = 180;
const RECENT_TEXTS_LIMIT = 4;

// Curated Pexels workspace/morning photography. The text itself is never
// prewritten: every morning Wesi AI generates a fresh thread for the selected
// persona. Telegram fetches the photo directly; text fallback keeps delivery
// independent from the external image host.
const PHOTOS = [
  "https://images.pexels.com/photos/33456309/pexels-photo-33456309.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/29791979/pexels-photo-29791979.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/15654210/pexels-photo-15654210.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/30234384/pexels-photo-30234384.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/35594938/pexels-photo-35594938.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/30234386/pexels-photo-30234386.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/31969694/pexels-photo-31969694.jpeg?cs=srgb&fm=jpg&w=1400",
];

function telegramApi(cfg, method, payload) {
  let response;
  try {
    response = $http.send({
      url: `https://api.telegram.org/bot${cfg.botToken}/${method}`,
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload || {}),
      timeout: 18,
    });
  } catch (_) { return {ok: false}; }
  const data = response && response.json && typeof response.json === "object" ? response.json : {};
  return {
    ok: !!response && response.statusCode >= 200 && response.statusCode < 300 && data.ok === true,
    result: data.result || null,
  };
}

function timezoneOffset(payload) {
  const prefs = payload && payload.notificationPrefs && typeof payload.notificationPrefs === "object"
    ? payload.notificationPrefs : {};
  return Math.max(-840, Math.min(840, Number(
    prefs.timezoneOffsetMinutes == null ? (payload && payload.timezoneOffsetMinutes || 0) : prefs.timezoneOffsetMinutes,
  )));
}

function localClock(nowMs, offsetMinutes) {
  const d = new Date(Number(nowMs == null ? Date.now() : nowMs) + Number(offsetMinutes || 0) * 60000);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth(),
    day: d.getUTCDate(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    dateKey: d.toISOString().slice(0, 10),
    dayNumber: Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) / DAY_MS),
  };
}

function speakerForDay(dayNumber) {
  return Math.abs(Number(dayNumber) - ANCHOR_DAY) % 2 === 0 ? "nirvana" : "zane";
}

function personaName(persona) {
  return persona === "nirvana" ? "Нирвана" : "Зейн";
}

function hash32(value) {
  const s = String(value || "");
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function photoFor(dateKey) {
  return PHOTOS[hash32(`${dateKey}:photo`) % PHOTOS.length];
}

function organizationName(selected) {
  const list = selected && Array.isArray(selected.organizations) ? selected.organizations : [];
  const hit = list.find((item) => String(item.id || "") === String(selected && selected.id || ""));
  return hit ? String(hit.name || hit.id || "") : String(selected && selected.id || "");
}

function todayTaskSnapshot(app, identity, organizationId, offset) {
  try {
    const result = taskTools.execute(
      {app: app},
      identity,
      "tasks_list",
      {dueMode: "today", timezoneOffsetMinutes: offset, limit: 3},
      organizationId,
    );
    if (!result || result.ok !== true) return {count: null, titles: []};
    const data = result.result || {};
    const tasks = Array.isArray(data.tasks) ? data.tasks : [];
    return {
      count: Math.max(0, Number(data.totalCount == null ? tasks.length : data.totalCount)),
      titles: tasks.slice(0, 3).map((item) => String(item.title || "").trim().slice(0, 120)).filter(Boolean),
    };
  } catch (_) {
    return {count: null, titles: []};
  }
}

function recentTexts(payload) {
  const state = payload && payload.morningState && typeof payload.morningState === "object"
    ? payload.morningState : {};
  const raw = Array.isArray(state.recentTexts) ? state.recentTexts : [];
  return raw.slice(-RECENT_TEXTS_LIMIT).map((value) => String(value || "").slice(0, MAX_THREAD_CHARS)).filter(Boolean);
}

function generationPrompt(persona, context) {
  const name = personaName(persona);
  const voice = persona === "nirvana"
    ? "Спокойный, тёплый, умный, уверенный голос. Больше смысла и внутренней собранности, меньше лозунгов."
    : "Энергичный, уверенный, прямой голос. Больше движения, решимости и ощущения старта дня, но без агрессивного инфобизнес-пафоса.";
  const taskLine = context.taskCount == null
    ? "Количество задач на сегодня серверу сейчас неизвестно. Просто напомни проверить актуальные задачи."
    : `На сегодня у сотрудника ${context.taskCount} задач с установленным сроком.`;
  const titles = context.taskTitles && context.taskTitles.length
    ? `Несколько актуальных задач для контекста, не обязательно перечислять их дословно: ${context.taskTitles.join(" | ")}.`
    : "Названия задач можно не упоминать.";
  const previous = context.recentTexts && context.recentTexts.length
    ? "\nНедавние утренние сообщения. НЕ повторяй их структуру, начало, метафоры и формулировки:\n- " + context.recentTexts.join("\n- ")
    : "";

  return [
    "[WESI_TELEGRAM_MORNING_THREAD]",
    `Сегодня ты ${name}. Сгенерируй НОВОЕ утреннее сообщение сотруднику WesiOS от первого лица именно в характере своей персоны.`,
    voice,
    "Язык: русский. Формат: 3–4 коротких абзаца, только чистый текст без markdown, заголовков, хэштегов и списков.",
    `Объём: ${MIN_THREAD_CHARS}–${MAX_THREAD_CHARS} символов.`,
    "Главная эмоциональная задача: поднять командный дух и дать ощущение, что мы не просто выполняем задачи по отдельности, а вместе строим сильную компанию и идём к общей большой цели.",
    "Естественно передай мысль, что сегодняшняя качественная работа создаёт наше общее будущее, вклад каждого важен, а впереди у команды большие возможности и великие дела. Не повторяй эту фразу дословно каждый день.",
    "Обязательно мягко напомни проверить актуальные задачи на сегодня, выбрать главный фокус и при необходимости помочь команде.",
    "Текст должен мотивировать действовать, а не вызывать чувство вины. Никаких манипуляций, давления, токсичной продуктивности и обещаний, что работа важнее личной жизни.",
    "Избегай корпоративных клише, пафоса, 'успешного успеха', банальных цитат, обращения 'воины/семья', фальшивой героики и чрезмерных восклицаний.",
    "Не выдумывай конкретные достижения, продажи, клиентов, дедлайны или цели компании, которых нет в контексте.",
    `Организация: ${context.organizationName || "WesiOS"}. Дата сотрудника: ${context.dateKey}.`,
    taskLine,
    titles,
    "Заверши живой авторской фразой, после которой хочется открыть задачи и начать день. Не подписывайся именем — подпись добавит Telegram-сервер.",
    previous,
  ].join("\n");
}

function cleanGenerated(value) {
  let text = String(value || "").trim();
  if (!text) return "";
  if (text.indexOf("```") === 0 && text.lastIndexOf("```") > 3) {
    text = text.replace(/^```(?:text|markdown)?\s*/i, "").replace(/```\s*$/, "").trim();
  }
  text = text.replace(/^\s*["«]+/, "").replace(/["»]+\s*$/, "").trim();
  text = text.replace(/\r/g, "").replace(/\n{3,}/g, "\n\n");
  if (text.length > MAX_THREAD_CHARS) {
    const clipped = text.slice(0, MAX_THREAD_CHARS + 1);
    const candidates = [clipped.lastIndexOf(". "), clipped.lastIndexOf("! "), clipped.lastIndexOf("? ")];
    const cut = Math.max.apply(null, candidates);
    text = (cut >= MIN_THREAD_CHARS ? clipped.slice(0, cut + 1) : clipped.slice(0, MAX_THREAD_CHARS)).trim();
  }
  return text.length >= MIN_THREAD_CHARS ? text : "";
}

function generateThread(payload, selected, snapshot, clock) {
  const persona = speakerForDay(clock.dayNumber);
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const personaBundle = personaRuntime.load(persona);
  const cfg = ai.readRelayConfig();
  const route = cfg.routes.fast || cfg.routes.pro || cfg.routes.maximum || "";
  if (!personaBundle.ready || !cfg.ready || !route) {
    return {ok: false, code: "WAI_MORNING_NOT_READY", persona: persona};
  }

  const context = {
    organizationName: organizationName(selected),
    dateKey: clock.dateKey,
    taskCount: snapshot.count,
    taskTitles: snapshot.titles,
    recentTexts: recentTexts(payload),
  };
  const morningRules = generationPrompt(persona, context);
  const requestId = "wai_tg_morning_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelay(cfg, {
    requestId: requestId,
    route: route,
    operation: "chat",
    input: {
      persona: persona,
      system: personaBundle.prompt + "\n\n" + morningRules,
      history: [],
      message: "Сгенерируй сегодняшнее утреннее сообщение для Telegram. Ответь только готовым текстом.",
      attachments: [],
    },
  }, requestId);
  if (!relay.ok) return {ok: false, code: relay.code || "WAI_MORNING_GENERATION_FAILED", persona: persona};
  const text = cleanGenerated(relay.answer);
  if (!text) return {ok: false, code: "WAI_MORNING_EMPTY", persona: persona};
  return {ok: true, persona: persona, text: text};
}

function morningCaption(persona, text, taskCount, orgName) {
  const name = personaName(persona);
  const lines = [
    `<b>Доброе утро · ${name}</b>`,
    orgName ? `<i>${tg.escapeHtml(orgName)}</i>` : "",
    "",
    tg.escapeHtml(text),
  ].filter((x) => x !== "");
  if (taskCount != null) lines.push("", `Сегодня задач в фокусе: <b>${Math.max(0, Number(taskCount || 0))}</b>`);
  lines.push("", `<i>— ${name}, WesiOS</i>`);
  return lines.join("\n");
}

function sendGeneratedMorning(cfg, app, payload, selected, snapshot, clock, generated) {
  const caption = morningCaption(
    generated.persona,
    generated.text,
    snapshot.count,
    organizationName(selected),
  );
  const keyboard = {inline_keyboard: [[{
    text: "✅ Задачи на сегодня",
    url: `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=tasks&org=${encodeURIComponent(selected.id)}`,
  }], [{
    text: "📊 Сводка дня",
    callback_data: tg.callback("brief", ""),
  }]]};

  let sent = telegramApi(cfg, "sendPhoto", {
    chat_id: payload.telegramChatId,
    photo: photoFor(clock.dateKey),
    caption: caption.slice(0, 1024),
    parse_mode: "HTML",
    protect_content: true,
    reply_markup: keyboard,
  });
  if (!sent.ok) {
    sent = telegramApi(cfg, "sendMessage", {
      chat_id: payload.telegramChatId,
      text: caption.slice(0, 4096),
      parse_mode: "HTML",
      disable_web_page_preview: true,
      reply_markup: keyboard,
    });
  }
  if (!sent.ok) return false;
  try { interactions.trackOutgoing(app, cfg, payload.telegramChatId, sent, "morning"); } catch (_) {}
  return true;
}

function runMorning(eventOrApp, nowMs) {
  const app = eventOrApp && eventOrApp.app ? eventOrApp.app : eventOrApp;
  if (!app) return 0;
  const cfg = store.config();
  if (!cfg.ready) return 0;
  let delivered = 0;

  for (const row of store.rows(app, store.COLL_LINKS, 5000)) {
    const payload = store.payloadOf(row);
    if (!payload || payload.revokedAt || !payload.telegramChatId || !payload.authUserId) continue;
    const prefs = payload.notificationPrefs && typeof payload.notificationPrefs === "object" ? payload.notificationPrefs : {};
    if (prefs.morning === false) continue;

    const offset = timezoneOffset(payload);
    const clock = localClock(nowMs == null ? Date.now() : nowMs, offset);
    if (clock.hour !== MORNING_HOUR) continue;

    const state = payload.morningState && typeof payload.morningState === "object" ? payload.morningState : {};
    if (String(state.lastLocalDate || "") === clock.dateKey) continue;

    const identity = store.resolveIdentityForAuth(app, payload.authUserId);
    if (!identity) continue;
    const selected = store.selectVisibleOrganization(app, identity, payload.activeOrganizationId);
    if (!selected.id) continue;
    const snapshot = todayTaskSnapshot(app, identity, selected.id, offset);
    const expectedPersona = speakerForDay(clock.dayNumber);

    let generated = null;
    if (
      String(state.pendingDate || "") === clock.dateKey &&
      String(state.pendingPersona || "") === expectedPersona &&
      cleanGenerated(state.pendingText)
    ) {
      generated = {ok: true, persona: expectedPersona, text: cleanGenerated(state.pendingText)};
    } else {
      generated = generateThread(payload, selected, snapshot, clock);
      if (!generated.ok) continue; // Retry on the next 5-minute cron tick during 08:00.
      state.pendingDate = clock.dateKey;
      state.pendingPersona = generated.persona;
      state.pendingText = generated.text;
      state.pendingGeneratedAt = new Date().toISOString();
      payload.morningState = state;
      store.updateLink(app, payload);
    }

    if (!sendGeneratedMorning(cfg, app, payload, selected, snapshot, clock, generated)) {
      continue; // Reuse pendingText next tick; don't pay for another model call.
    }

    const recent = Array.isArray(state.recentTexts) ? state.recentTexts.slice(-RECENT_TEXTS_LIMIT + 1) : [];
    recent.push(generated.text);
    state.lastLocalDate = clock.dateKey;
    state.lastPersona = generated.persona;
    state.lastSentAt = new Date().toISOString();
    state.recentTexts = recent;
    state.pendingDate = null;
    state.pendingPersona = null;
    state.pendingText = null;
    state.pendingGeneratedAt = null;
    payload.morningState = state;
    store.updateLink(app, payload);
    delivered++;
  }
  return delivered;
}

module.exports = {
  ANCHOR_DAY,
  MORNING_HOUR,
  MIN_THREAD_CHARS,
  MAX_THREAD_CHARS,
  localClock,
  speakerForDay,
  personaName,
  photoFor,
  generationPrompt,
  cleanGenerated,
  morningCaption,
  runMorning,
};
