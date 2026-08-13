routerAdd("POST", "/api/wesi/ai/lobby", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personas = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);

  const body = e.requestInfo().body || {};
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const mode = String(body.lobbyMode || "smart").trim().toLowerCase();
  const message = String(body.message || "").trim();
  const summary = String(body.summary || "").trim();
  const history = Array.isArray(body.messages) ? body.messages : [];
  const memory = body.memory && typeof body.memory === "object" ? body.memory : {};

  if (["fast", "pro", "maximum"].indexOf(tier) < 0) throw new BadRequestError("Некорректный уровень Wesi AI");
  if (["both", "smart"].indexOf(mode) < 0) throw new BadRequestError("Некорректный режим лобби");
  if (!message || message.length > 32000) throw new BadRequestError("Некорректное сообщение Wesi AI");
  if (summary.length > 64000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
  if (body.provider != null || body.model != null || body.providerModel != null) throw new BadRequestError("Недоступная настройка Wesi AI");

  const zane = personas.load("zane");
  const nirvana = personas.load("nirvana");
  if (!zane.ready || !nirvana.ready) return e.json(503, {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"});

  const cfg = ai.readRelayConfig();
  const route = cfg.routes[tier] || "";
  if (!cfg.ready || !route) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  const cleanHistory = [];
  for (const item of history) {
    if (!item || typeof item !== "object") continue;
    const author = String(item.author || item.role || "").toLowerCase();
    const text = String(item.text || item.content || "");
    if (["user", "zane", "nirvana", "tool"].indexOf(author) < 0) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение в контексте");
    cleanHistory.push({author: author, text: text});
  }
  const cleanMemory = ai.sanitizeMemory(memory);
  const rootRequestId = "wai_lobby_" + Date.now() + "_" + $security.randomString(10);

  const relayCall = function(operation, phase, system, extraHistory) {
    const requestId = rootRequestId + "_" + phase;
    const payload = {
      requestId: requestId,
      route: route,
      operation: operation,
      input: {
        system: system,
        history: cleanHistory.concat(Array.isArray(extraHistory) ? extraHistory : []),
        message: message,
      },
    };
    const raw = JSON.stringify(payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = $security.hs256(timestamp + "." + raw, cfg.sharedSecret);
    let relay;
    try {
      relay = $http.send({
        url: cfg.url.replace(/\/$/, "") + "/v1/wesi-ai",
        method: "POST",
        body: raw,
        headers: {
          "Content-Type": "application/json",
          "X-Wesi-Request-Id": requestId,
          "X-Wesi-Timestamp": timestamp,
          "X-Wesi-Signature": signature,
        },
        timeout: 120,
      });
    } catch (_) {
      return {ok: false, code: "WAI_RELAY_UNAVAILABLE"};
    }
    if (!relay || relay.statusCode < 200 || relay.statusCode >= 300) return {ok: false, code: "WAI_RELAY_BAD_RESPONSE"};
    const result = relay.json && typeof relay.json === "object" ? relay.json : {};
    const answer = String(result.answer || "").trim();
    return answer ? {ok: true, answer: answer} : {ok: false, code: "WAI_EMPTY_RESPONSE"};
  };

  let order = ["zane", "nirvana"];
  if (mode === "smart") {
    const routerSystem = [
      "WESI_AI_LOBBY_ROUTER",
      "Ты внутренний маршрутизатор Wesi AI на основном сервере.",
      "Не отвечай пользователю и не раскрывай техническую модель.",
      "Выбери, кто реально нужен для текущего запроса:",
      "ZANE — техника, код, расчёты, финансы, аналитика, управление рабочими задачами.",
      "NIRVANA — творчество, визуал, музыка, видео, тексты, creative direction.",
      "ZANE_NIRVANA — сначала Зейн, потом Нирвана, когда задача смешанная.",
      "NIRVANA_ZANE — сначала Нирвана, потом Зейн, когда творческая идея требует технической/деловой проверки.",
      "Если пользователь явно просит обоих или зовёт вторую персону — выбери вариант с двумя.",
      "Верни только один токен: ZANE, NIRVANA, ZANE_NIRVANA или NIRVANA_ZANE.",
    ].join("\n");
    const routed = relayCall("route", "route", routerSystem, []);
    if (routed.ok) {
      const token = routed.answer.toUpperCase().replace(/[^A-Z_]/g, "");
      if (token === "ZANE") order = ["zane"];
      else if (token === "NIRVANA") order = ["nirvana"];
      else if (token === "NIRVANA_ZANE") order = ["nirvana", "zane"];
      else order = ["zane", "nirvana"];
    }
  }

  const messages = [];
  const turnHistory = [];
  for (const persona of order) {
    const profile = persona === "zane" ? zane : nirvana;
    const personaMemory = persona === "zane" ? cleanMemory.zane : cleanMemory.nirvana;
    const parts = [profile.prompt];
    parts.push("[WESI_AI_LOBBY]\nТы сейчас находишься в общем Lobby. Сохраняй только свою личность и не пиши реплики за другого участника.");
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
    if (cleanMemory.shared.length) parts.push("[WESI_AI_SHARED_MEMORY]\n" + cleanMemory.shared.join("\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
    if (turnHistory.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\n" + JSON.stringify(turnHistory));

    const generated = relayCall("lobby", persona, parts.join("\n\n"), turnHistory);
    if (!generated.ok) {
      if (!messages.length) return e.json(503, {ok: false, code: generated.code, requestId: rootRequestId});
      messages.push({author: "system", text: persona === "zane" ? "Зейн временно не ответил" : "Нирвана временно не ответила", error: generated.code});
      continue;
    }
    const item = {author: persona, text: generated.answer};
    messages.push(item);
    turnHistory.push(item);
  }

  return e.json(200, {
    ok: true,
    requestId: rootRequestId,
    persona: "lobby",
    tier: tier,
    lobbyMode: mode,
    participants: order,
    messages: messages,
  });
}, $apis.requireAuth("users"));
