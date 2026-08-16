function clean(value) {
  return String(value || "").trim().toLowerCase().replace(/ё/g, "е");
}

function containsAny(text, values) {
  for (const value of values) {
    if (text.indexOf(value) >= 0) return true;
  }
  return false;
}

function lastPersona(history) {
  const items = Array.isArray(history) ? history : [];
  for (let i = items.length - 1; i >= 0; i--) {
    const author = clean(items[i] && items[i].author);
    if (author === "zane" || author === "nirvana") return author;
  }
  return "";
}

function mentionedPersona(text) {
  const hasZane = containsAny(text, ["зейн", "zane"]);
  const hasNirvana = containsAny(text, ["нирван", "nirvana"]);
  if (hasZane && !hasNirvana) return "zane";
  if (hasNirvana && !hasZane) return "nirvana";
  return "";
}

function opposite(persona) {
  if (persona === "zane") return "nirvana";
  if (persona === "nirvana") return "zane";
  return "";
}

function handoffSequence(message, history) {
  const text = clean(message);
  const summon = containsAny(text, [
    "позови", "позвать", "пригласи", "пригласить", "подключи",
    "подключить", "вызови", "вызвать", "передай слово", "дай слово",
    "call him", "call her", "bring zane", "bring nirvana"
  ]);
  if (!summon) return null;

  const previous = lastPersona(history);
  let target = mentionedPersona(text);
  if (!target && containsAny(text, [
    "позови его", "позови ее", "позови её", "другого", "другую",
    "второго", "вторую", "его сюда", "ее сюда", "её сюда"
  ])) {
    target = opposite(previous);
  }
  if (!target) target = opposite(previous) || "nirvana";

  let caller = previous;
  if (!caller || caller === target) {
    const hasZane = containsAny(text, ["зейн", "zane"]);
    const hasNirvana = containsAny(text, ["нирван", "nirvana"]);
    if (hasZane && hasNirvana) caller = opposite(target);
  }
  if (caller && caller !== target) return [caller, target];
  return [target];
}

function deterministicRoute(message, history) {
  const text = clean(message);
  if (!text) return null;

  const handoff = handoffSequence(text, history);
  if (handoff) return handoff;

  const explicit = mentionedPersona(text);
  if (explicit) return [explicit];

  const creative = containsAny(text, [
    "стих", "стихотвор", "поэм", "рифм", "текст песни", "лирик",
    "облож", "дизайн", "визуал", "арт", "креатив", "творчес",
    "сюжет", "сценар", "концепт", "мелод", "музык", "бит"
  ]);
  const technical = containsAny(text, [
    "код", "сервер", "билд", "сборк", "ошиб", "баг", "лог", "api",
    "github", "firebase", "деплой", "релиз", "архитект", "тест",
    "финанс", "деньг", "денег", "сколько денег", "остаток", "баланс",
    "бюджет", "доход", "расход", "транзак", "счет", "счёт",
    "организац", "crm", "задач", "аналитик"
  ]);

  if (creative && !technical) return ["nirvana"];
  if (technical && !creative) return ["zane"];
  if (creative && technical) return ["zane", "nirvana"];
  return null;
}

module.exports = {
  handoff: handoffSequence,
  choose: function(ai, cfg, route, requestId, message, history) {
    const deterministic = deterministicRoute(message, history);
    if (deterministic) return deterministic;

    const payload = {requestId, route, operation: "lobby", input: {
      system: "WESI_AI_LOBBY_ROUTER\nChoose ZANE for technical/finance/work tasks, NIRVANA for creative/media tasks, and both for mixed requests. Never decide who should imitate whom: each selected persona speaks only as itself. Return only ZANE, NIRVANA, ZANE_NIRVANA or NIRVANA_ZANE.",
      history, message
    }};
    const result = ai.callRelay(cfg, payload, requestId);
    if (!result.ok) return ["zane"];
    const token = result.answer.toUpperCase().replace(/[^A-Z_]/g, "");
    if (token === "ZANE") return ["zane"];
    if (token === "NIRVANA") return ["nirvana"];
    if (token === "NIRVANA_ZANE") return ["nirvana", "zane"];
    if (token === "ZANE_NIRVANA") return ["zane", "nirvana"];
    return ["zane"];
  },
  _test: {
    deterministicRoute,
    handoffSequence,
    lastPersona
  }
};
