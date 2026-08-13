routerAdd("GET", "/api/wesi/ai/capabilities", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = ai.readRelayConfig();
  return e.json(200, {
    product: "Wesi AI",
    tiers: ["fast", "pro", "maximum"],
    personas: ["zane", "nirvana", "lobby"],
    lobbyModes: ["both", "smart"],
    relayReady: cfg.ready,
    features: {localFirstChats: true, handoff: true, lobby: true, streaming: false, media: false, wesiTools: false}
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/chat", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  const persona = String(body.persona || "").trim().toLowerCase();
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const message = String(body.message || "").trim();
  if (["zane", "nirvana", "lobby"].indexOf(persona) < 0) throw new BadRequestError("Некорректный режим Wesi AI");
  if (["fast", "pro", "maximum"].indexOf(tier) < 0) throw new BadRequestError("Некорректный уровень Wesi AI");
  if (!message || message.length > 32000) throw new BadRequestError("Некорректное сообщение Wesi AI");
  if (body.provider != null || body.model != null) throw new BadRequestError("Недоступная настройка Wesi AI");
  const cfg = ai.readRelayConfig();
  if (!cfg.ready || !cfg.routes[tier]) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  return e.json(503, {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"});
}, $apis.requireAuth("users"));
