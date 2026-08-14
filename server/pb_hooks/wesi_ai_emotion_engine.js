const EMOTIONS = ["joy", "trust", "anticipation", "surprise", "sadness", "anxiety", "anger", "aversion"];

function cleanPersonaState(raw) {
  raw = raw && typeof raw === "object" ? raw : {};
  const levelsRaw = raw.levels && typeof raw.levels === "object" ? raw.levels : {};
  const levels = {};
  for (const key of EMOTIONS) {
    const value = Number(levelsRaw[key] || 0);
    if (Number.isFinite(value) && value > 0) levels[key] = Math.max(0, Math.min(1, value));
  }
  const traces = [];
  const rawTraces = Array.isArray(raw.traces) ? raw.traces : [];
  for (const item of rawTraces.slice(-12)) {
    if (!item || typeof item !== "object") continue;
    const summary = String(item.summary || "").trim().slice(0, 500);
    if (!summary) continue;
    traces.push({
      id: String(item.id || "").slice(0, 120),
      subject: String(item.subject || "user").slice(0, 40),
      summary: summary,
      weight: Math.max(0, Math.min(1, Number(item.weight || 0))),
      createdAt: String(item.createdAt || ""),
      updatedAt: String(item.updatedAt || ""),
      unresolved: item.unresolved !== false
    });
  }
  return {
    levels: levels,
    traces: traces,
    updatedAt: String(raw.updatedAt || ""),
    stance: String(raw.stance || "").trim().slice(0, 500)
  };
}

function sanitizeSnapshot(raw) {
  raw = raw && typeof raw === "object" ? raw : {};
  return {
    zane: cleanPersonaState(raw.zane),
    nirvana: cleanPersonaState(raw.nirvana)
  };
}

function parseJson(text) {
  let value = String(text || "").trim();
  if (value.startsWith("```json")) value = value.slice(7, value.lastIndexOf("```")).trim();
  else if (value.startsWith("```") && value.lastIndexOf("```") > 3) value = value.slice(3, value.lastIndexOf("```")).trim();
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
}

function normalizeResult(parsed, fallback) {
  if (!parsed || typeof parsed !== "object") return fallback;
  const now = new Date().toISOString();
  const output = {};
  for (const persona of ["zane", "nirvana"]) {
    const source = parsed[persona] && typeof parsed[persona] === "object" ? parsed[persona] : fallback[persona];
    const levels = {};
    const rawLevels = source.levels && typeof source.levels === "object" ? source.levels : {};
    for (const key of EMOTIONS) {
      const value = Number(rawLevels[key] || 0);
      if (Number.isFinite(value) && value >= 0.03) levels[key] = Math.max(0, Math.min(1, value));
    }
    const traces = [];
    const rawTraces = Array.isArray(source.traces) ? source.traces : [];
    for (const trace of rawTraces.slice(-12)) {
      if (!trace || typeof trace !== "object") continue;
      const summary = String(trace.summary || "").trim().slice(0, 500);
      if (!summary) continue;
      traces.push({
        id: String(trace.id || (persona + "_" + Date.now() + "_" + traces.length)).slice(0, 120),
        subject: String(trace.subject || "user").slice(0, 40),
        summary: summary,
        weight: Math.max(0, Math.min(1, Number(trace.weight || 0.35))),
        createdAt: String(trace.createdAt || now),
        updatedAt: now,
        unresolved: trace.unresolved !== false
      });
    }
    output[persona] = {
      levels: levels,
      traces: traces,
      updatedAt: now,
      stance: String(source.stance || "").trim().slice(0, 500)
    };
  }
  return output;
}

module.exports = {
  emotions: EMOTIONS,
  sanitize: sanitizeSnapshot,

  evaluate: function(ai, cfg, requestId, persona, message, history, current) {
    const fallback = sanitizeSnapshot(current);
    const route = String(cfg.routes.fast || cfg.routes.pro || cfg.routes.maximum || "").trim();
    if (!route) return {ok: false, emotions: fallback};
    const recent = Array.isArray(history) ? history.slice(-12) : [];
    const system = [
      "WESI_AI_EMOTION_ENGINE",
      "Ты оцениваешь внутреннее эмоциональное состояние двух вымышленных AI-персон WesiOS: Зейна и Нирваны.",
      "Это не диагноз человека. Эмоции должны быть естественными, умеренными и контекстными, без театральности.",
      "Используй 8 шкал 0..1: joy, trust, anticipation, surprise, sadness, anxiety, anger, aversion.",
      "Можно сочетать несколько эмоций. Не меняй состояние резко без сильного контекстного события.",
      "Учитывай текущие levels, traces и stance. Положительная поддержка повышает joy/trust; конфликт, насмешки и предательство могут повышать sadness/anger/aversion; неопределённость — anxiety/anticipation.",
      "Если возникло значимое межличностное событие, добавь короткий trace: subject=user|zane|nirvana, summary, weight 0..1, unresolved true/false.",
      "Если было искреннее извинение или примирение, можно уменьшить weight и отметить trace resolved. Старые обиды не должны длиться вечно.",
      "stance — краткая внутренняя установка, максимум 1 предложение: например 'всё ещё ждёт извинений от Зейна'.",
      "Верни ТОЛЬКО JSON объекта {zane:{levels,traces,stance},nirvana:{levels,traces,stance}}. Не пиши объяснений."
    ].join("\n");
    const payload = {
      requestId: requestId,
      route: route,
      operation: "chat",
      input: {
        system: system,
        history: [],
        message: JSON.stringify({persona: persona, current: fallback, recent: recent, newMessage: message})
      }
    };
    const generated = ai.callRelay(cfg, payload, requestId);
    if (!generated.ok) return {ok: false, emotions: fallback};
    return {ok: true, emotions: normalizeResult(parseJson(generated.answer), fallback)};
  }
};
