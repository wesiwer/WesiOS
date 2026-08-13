routerAdd("GET", "/api/wesi/ai/capabilities", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = ai.readRelayConfig();
  const personasReady = personaRuntime.load("zane").ready && personaRuntime.load("nirvana").ready;
  return e.json(200, {
    product: "Wesi AI",
    tiers: ["fast", "pro", "maximum"],
    personas: ["zane", "nirvana", "lobby"],
    lobbyModes: ["both", "smart"],
    ready: cfg.ready && personasReady,
    features: {localFirstChats: true, handoff: true, lobby: true, streaming: false, media: false, wesiTools: false}
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/chat", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  const persona = String(body.persona || "").trim().toLowerCase();
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const lobbyMode = String(body.lobbyMode || "smart").trim().toLowerCase();
  const message = String(body.message || "").trim();
  const summary = String(body.summary || "").trim();
  const history = Array.isArray(body.messages) ? body.messages : [];
  const memory = body.memory && typeof body.memory === "object" ? body.memory : {};

  if (["zane", "nirvana", "lobby"].indexOf(persona) < 0) throw new BadRequestError("Некорректный режим Wesi AI");
  if (["fast", "pro", "maximum"].indexOf(tier) < 0) throw new BadRequestError("Некорректный уровень Wesi AI");
  if (persona === "lobby" && ["both", "smart"].indexOf(lobbyMode) < 0) throw new BadRequestError("Некорректный режим лобби");
  if (!message || message.length > 32000) throw new BadRequestError("Некорректное сообщение Wesi AI");
  if (summary.length > 64000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
  if (body.provider != null || body.model != null || body.providerModel != null) throw new BadRequestError("Недоступная настройка Wesi AI");

  const personaBundle = personaRuntime.load(persona);
  if (!personaBundle.ready) return e.json(503, {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"});
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
  const systemParts = [personaBundle.prompt];
  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\n" + cleanMemory.shared.join("\n"));
  const personaMemory = persona === "zane" ? cleanMemory.zane : persona === "nirvana" ? cleanMemory.nirvana : cleanMemory.zane.concat(cleanMemory.nirvana);
  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
  if (persona === "lobby") systemParts.push("[WESI_AI_LOBBY_MODE]\n" + lobbyMode);

  const requestId = "wai_" + Date.now() + "_" + $security.randomString(12);
  const payload = {
    requestId: requestId,
    route: route,
    operation: persona === "lobby" ? "lobby" : "chat",
    input: {system: systemParts.join("\n\n"), history: cleanHistory, message: message}
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
      headers: {"Content-Type": "application/json", "X-Wesi-Request-Id": requestId, "X-Wesi-Timestamp": timestamp, "X-Wesi-Signature": signature},
      timeout: 120
    });
  } catch (_) {
    return e.json(503, {ok: false, code: "WAI_RELAY_UNAVAILABLE"});
  }
  if (!relay || relay.statusCode < 200 || relay.statusCode >= 300) return e.json(502, {ok: false, code: "WAI_RELAY_BAD_RESPONSE", requestId: requestId});
  const result = relay.json && typeof relay.json === "object" ? relay.json : {};
  const answer = String(result.answer || "").trim();
  if (!answer) return e.json(502, {ok: false, code: "WAI_EMPTY_RESPONSE", requestId: requestId});
  return e.json(200, {
    ok: true,
    requestId: requestId,
    persona: persona,
    tier: tier,
    answer: answer,
    handoff: result.handoff && typeof result.handoff === "object" ? result.handoff : null,
    lobby: result.lobby && typeof result.lobby === "object" ? result.lobby : null
  });
}, $apis.requireAuth("users"));
