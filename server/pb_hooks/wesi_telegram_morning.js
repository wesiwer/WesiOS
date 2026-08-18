const tg = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_lib.js");
const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");
const interactions = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_interactions.js");
const taskTools = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_task_tools.js");

const DAY_MS = 24 * 60 * 60 * 1000;
const ANCHOR_DAY = Math.floor(Date.UTC(2026, 7, 18) / DAY_MS); // 18 Aug 2026 = Nirvana.
const MORNING_HOUR = 8;

const PHOTOS = [
  "https://images.pexels.com/photos/33456309/pexels-photo-33456309.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/29791979/pexels-photo-29791979.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/15654210/pexels-photo-15654210.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/30234384/pexels-photo-30234384.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/35594938/pexels-photo-35594938.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/30234386/pexels-photo-30234386.jpeg?cs=srgb&fm=jpg&w=1400",
  "https://images.pexels.com/photos/31969694/pexels-photo-31969694.jpeg?cs=srgb&fm=jpg&w=1400",
];

const NIRVANA = [
  "Доброе утро. Не пытайтесь выиграть весь месяц за один день — выиграйте сегодняшний фокус. Откройте задачи, выберите главное и сделайте первый сильный шаг до того, как день начнёт выбирать за вас.",
  "Новый день — это не повтор вчерашнего, а ещё одна возможность немного изменить траекторию. Проверьте задачи, уберите лишний шум и вложите внимание туда, где результат действительно двигает компанию вперёд.",
  "Утро хорошо тем, что день ещё никому ничего не должен. Используйте эту тишину правильно: посмотрите задачи, определите одну вещь, после которой вечер будет ощущаться не зря прожитым, и начните с неё.",
  "Работа становится будущим не в момент большого прорыва, а в сотнях обычных дней, когда мы всё равно делаем нужное. Сегодня один из них. Проверьте список задач и создайте маленькое преимущество для себя завтрашнего.",
  "Не обязательно чувствовать вдохновение, чтобы начать. Иногда вдохновение приходит уже после первых двадцати минут хорошей работы. Откройте задачи, выберите направление и дайте себе шанс войти в ритм.",
  "Сегодняшние решения незаметно становятся завтрашней реальностью. Поэтому начните спокойно: что действительно важно, что можно закрыть сегодня, что приблизит команду к сильному результату? Проверьте задачи и зафиксируйте фокус.",
  "Сильная работа редко выглядит героически. Чаще это ясная голова, несколько правильных приоритетов и выполненные обещания самому себе. Доброе утро. Посмотрите, что ждёт вас сегодня, и соберите день вокруг главного.",
  "Пусть сегодня будет меньше суеты и больше смысла. Время всё равно пройдёт — вопрос только в том, что останется после него. Проверьте актуальные задачи и выберите то, что создаёт реальную ценность.",
  "Будущее компании складывается из сегодняшних действий гораздо чаще, чем из красивых планов. Утро — хорошее время сверить направление. Посмотрите задачи, расставьте приоритеты и двигайтесь без лишнего шума.",
  "Не нужно успеть всё. Нужно не потерять главное. Откройте задачи на сегодня, выберите несколько действительно важных точек и оставьте себе пространство сделать их качественно.",
  "Доброе утро. Сделайте этот день опорой для следующего: одна закрытая сложная задача, одно принятое решение, один шаг, который давно откладывался. Начните с актуального списка и двигайтесь спокойно.",
  "Есть дни, которые меняют всё, и есть дни, которые готовят для них почву. Мы никогда заранее не знаем, какой сегодня. Поэтому просто сделайте свою часть хорошо. Проверьте задачи — и начните.",
];

const ZANE = [
  "Доброе утро. Сегодня без долгого разгона: открыть задачи, выбрать главное, закрыть первый пункт. Будущее любит скорость, но ещё больше оно любит людей, которые доводят начатое до результата.",
  "Новый день уже запущен. Пока остальные только собираются, можно успеть создать себе фору. Проверьте задачи на сегодня, заберите самый важный приоритет и сделайте так, чтобы к обеду уже было чем гордиться.",
  "План простой: меньше вкладок, меньше шума, больше законченных вещей. Откройте задачи, выберите то, что реально двигает бизнес, и атакуйте это первым. Хороший день начинается с конкретного результата.",
  "Сегодняшняя работа — это депозит в жизнь, которую вы хотите получить позже. Проценты начисляются не за намерения. Проверьте список задач и положите в этот день что-нибудь весомое.",
  "Не ждите идеального настроения. Сделайте первое действие — настроение догонит. Задачи уже знают, где лежит следующий уровень. Осталось открыть их и начать.",
  "Утро. Кофе можно допить по дороге, а вот хороший импульс лучше не откладывать. Проверьте задачи, найдите самую неприятную важную штуку и снимите её с доски раньше, чем она начнёт висеть над всем днём.",
  "День не обязан быть лёгким, чтобы быть сильным. Нам нужен не идеальный график, а прогресс. Посмотрите задачи на сегодня и выберите тот результат, который вечером будет говорить сам за себя.",
  "Сегодня у вас снова есть восемь рабочих часов, чтобы немного изменить положение вещей. Используйте их не на ощущение занятости, а на реальные завершения. Сначала — актуальные задачи.",
  "Будущее редко приходит эффектно. Обычно оно собирается утром, когда кто-то просто сел и сделал работу лучше, чем вчера. Сегодня этот кто-то — вы. Откройте задачи и поехали.",
  "Маленький вызов на сегодня: до первого большого отвлечения закрыть одну важную вещь. Не обсуждать, не готовиться бесконечно — закрыть. Список задач подскажет, с чего начать.",
  "Доброе утро. Если день всё равно пройдёт, пусть он хотя бы оставит после себя результат. Проверьте задачи, определите три главных пункта и не отдавайте фокус мелочам.",
  "Компания растёт не от количества разговоров о росте. Она растёт, когда люди каждый день делают чуть больше правильных вещей. Откройте задачи. Сегодня есть шанс добавить ещё один такой день.",
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
  const d = new Date(Number(nowMs || Date.now()) + Number(offsetMinutes || 0) * 60000);
  return {
    year: d.getUTCFullYear(), month: d.getUTCMonth(), day: d.getUTCDate(),
    hour: d.getUTCHours(), minute: d.getUTCMinutes(),
    dateKey: d.toISOString().slice(0, 10),
    dayNumber: Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) / DAY_MS),
  };
}

function speakerForDay(dayNumber) {
  return Math.abs(Number(dayNumber) - ANCHOR_DAY) % 2 === 0 ? "nirvana" : "zane";
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

function variantFor(speaker, dateKey, telegramUserId) {
  const source = speaker === "nirvana" ? NIRVANA : ZANE;
  return source[hash32(`${dateKey}:${telegramUserId}:${speaker}`) % source.length];
}

function photoFor(dateKey, telegramUserId) {
  return PHOTOS[hash32(`${dateKey}:${telegramUserId}:photo`) % PHOTOS.length];
}

function todayTaskCount(app, identity, organizationId, offset) {
  try {
    const result = taskTools.execute(
      {app: app}, identity, "tasks_list",
      {dueMode: "today", timezoneOffsetMinutes: offset, limit: 3},
      organizationId,
    );
    if (result && result.ok === true) return Math.max(0, Number(result.result.totalCount || 0));
  } catch (_) {}
  return null;
}

function morningCaption(speaker, text, taskCount, organizationName) {
  const name = speaker === "nirvana" ? "Нирвана" : "Зейн";
  const lines = [
    `<b>Доброе утро · ${name}</b>`,
    organizationName ? `<i>${tg.escapeHtml(organizationName)}</i>` : "",
    "",
    tg.escapeHtml(text),
    "",
  ].filter((x) => x !== "");
  if (taskCount == null) lines.push("Перед стартом проверьте актуальные задачи на сегодня.");
  else if (taskCount === 0) lines.push("На сегодня нет задач с установленным сроком — хороший момент сверить приоритеты и создать следующий шаг.");
  else lines.push(`Сегодня в фокусе задач: <b>${taskCount}</b>. Проверьте список перед началом работы.`);
  lines.push("", `<i>— ${name}, WesiOS</i>`);
  return lines.join("\n");
}

function sendMorning(cfg, app, payload, identity, selected, clock) {
  const speaker = speakerForDay(clock.dayNumber);
  const text = variantFor(speaker, clock.dateKey, payload.telegramUserId);
  const taskCount = todayTaskCount(app, identity, selected.id, timezoneOffset(payload));
  const org = selected.organizations && selected.organizations.find((x) => String(x.id) === String(selected.id));
  const caption = morningCaption(speaker, text, taskCount, org && org.name || "");
  const keyboard = {inline_keyboard: [[{
    text: "✅ Задачи на сегодня",
    url: `${cfg.publicBaseUrl}/api/wesi/telegram/open?target=tasks&org=${encodeURIComponent(selected.id)}`,
  }], [{
    text: "📊 Сводка дня",
    callback_data: tg.callback("brief", ""),
  }]]};
  const photo = photoFor(clock.dateKey, payload.telegramUserId);
  let sent = telegramApi(cfg, "sendPhoto", {
    chat_id: payload.telegramChatId,
    photo: photo,
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
  payload.morningState = {
    lastLocalDate: clock.dateKey,
    lastSpeaker: speaker,
    lastSentAt: new Date().toISOString(),
  };
  store.updateLink(app, payload);
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
    const clock = localClock(nowMs == null ? Date.now() : nowMs, timezoneOffset(payload));
    if (clock.hour !== MORNING_HOUR) continue;
    const state = payload.morningState && typeof payload.morningState === "object" ? payload.morningState : {};
    if (String(state.lastLocalDate || "") === clock.dateKey) continue;
    const identity = store.resolveIdentityForAuth(app, payload.authUserId);
    if (!identity) continue;
    const selected = store.selectVisibleOrganization(app, identity, payload.activeOrganizationId);
    if (!selected.id) continue;
    if (sendMorning(cfg, app, payload, identity, selected, clock)) delivered++;
  }
  return delivered;
}

module.exports = {
  ANCHOR_DAY,
  MORNING_HOUR,
  localClock,
  speakerForDay,
  variantFor,
  photoFor,
  morningCaption,
  runMorning,
};
