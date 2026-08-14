routerAdd("POST", "/api/wesi/ai/context/compact", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);

  const body = e.requestInfo().body || {};
  const existingSummary = String(body.existingSummary || "").trim();
  const messages = Array.isArray(body.messages) ? body.messages : [];
  if (existingSummary.length > 64000) throw new BadRequestError("Слишком большой summary Wesi AI");
  if (!messages.length || messages.length > 64) throw new BadRequestError("Некорректный пакет контекста Wesi AI");

  const clean = [];
  let chars = 0;
  for (const item of messages) {
    if (!item || typeof item !== "object") continue;
    const author = String(item.author || item.role || "").toLowerCase();
    const text = String(item.text || item.content || "").trim();
    if (["user", "zane", "nirvana"].indexOf(author) < 0 || !text) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение контекста");
    chars += text.length;
    if (chars > 180000) throw new BadRequestError("Слишком большой пакет контекста Wesi AI");
    clean.push({author: author, text: text});
  }
  if (!clean.length) throw new BadRequestError("Пустой пакет контекста Wesi AI");

  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  const route = String(cfg.routes.fast || cfg.routes.pro || cfg.routes.maximum || "").trim();
  if (!route) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  const system = [
    "Ты — внутренний инструмент Wesi AI Context Optimizer.",
    "Сожми старый контекст диалога в точную структурированную память для следующей модели.",
    "Не добавляй новых фактов и не делай предположений. Если информация спорная или менялась, сохрани последнее явно подтвержденное состояние и отметь конфликт.",
    "Обязательно сохрани: факты о пользователе и проекте; принятые решения; текущие цели; ограничения и запреты; незавершенные задачи и вопросы; важные идентификаторы/пути/ссылки без секретов; результаты действий и инструментов, если они присутствуют в тексте; договоренности о стиле и поведении.",
    "Отбрасывай приветствия, повторы, промежуточные формулировки, устаревшие варианты после явного решения и несущественные детали.",
    "Не включай скрытые рассуждения модели. Не сохраняй секреты, пароли, токены и приватные ключи даже если они встречаются в тексте.",
    "Верни только итоговую выжимку на русском языке, без markdown-ограждений. Используй короткие секции: Факты; Решения; Цели; Ограничения; Незавершенное; Важный контекст."
  ].join("\n");

  const contextText = [
    existingSummary ? "ПРЕДЫДУЩАЯ ВЫЖИМКА:\n" + existingSummary : "",
    "НОВЫЙ СТАРЫЙ КОНТЕКСТ ДЛЯ СЖАТИЯ:\n" + JSON.stringify(clean)
  ].filter(Boolean).join("\n\n");

  const requestId = "wai_compact_" + Date.now() + "_" + $security.randomString(12);
  const generated = ai.callRelay(cfg, {
    requestId: requestId,
    route: route,
    operation: "chat",
    input: {
      system: system,
      history: [],
      message: contextText
    }
  }, requestId);

  if (!generated.ok) {
    return e.json(generated.status, {
      ok: false,
      code: generated.code || "WAI_CONTEXT_COMPACTION_FAILED"
    });
  }
  const summary = String(generated.answer || "").trim();
  if (!summary) return e.json(502, {ok: false, code: "WAI_CONTEXT_COMPACTION_FAILED"});
  if (summary.length > 64000) return e.json(502, {ok: false, code: "WAI_CONTEXT_COMPACTION_TOO_LARGE"});

  return e.json(200, {
    ok: true,
    summary: summary,
    compactedCount: clean.length,
    requestId: requestId
  });
}, $apis.requireAuth("users"));
