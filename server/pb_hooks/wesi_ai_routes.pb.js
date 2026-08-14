routerAdd("GET", "/api/wesi/ai/capabilities", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = ai.readRelayConfig();
  const personasReady = personaRuntime.load("zane").ready && personaRuntime.load("nirvana").ready;
  const ultraReady = !!(cfg.routes.ultra.low || cfg.routes.ultra.medium || cfg.routes.ultra.high);
  return e.json(200, {
    product: "Wesi AI",
    tiers: ["fast", "pro", "maximum", "ultra"],
    personas: ["zane", "nirvana", "lobby"],
    lobbyModes: ["both", "smart"],
    ready: cfg.ready && personasReady,
    features: {
      localFirstChats: true,
      handoff: true,
      lobby: true,
      emotions: true,
      adaptiveContext: true,
      voiceConversation: true,
      naturalTts: cfg.ready,
      streaming: false,
      media: cfg.ready,
      imageGeneration: cfg.ready,
      videoGeneration: cfg.ready,
      musicGeneration: cfg.ready,
      ultraRouting: ultraReady,
      modelLimits: cfg.ready,
      wesiTools: tools.definitions(e, ctx).length > 0
    }
  });
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/ai/limits", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});
  const requestId = "wai_limits_" + Date.now() + "_" + $security.randomString(12);
  const routes = {
    fast: cfg.routes.fast,
    pro: cfg.routes.pro,
    maximum: cfg.routes.maximum,
    ultraLow: cfg.routes.ultra.low,
    ultraMedium: cfg.routes.ultra.medium,
    ultraHigh: cfg.routes.ultra.high
  };
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "limits",
    input: {routes: routes}
  }, requestId, 30);
  if (!relay.ok) return e.json(relay.status, {ok: false, code: relay.code});
  return e.json(200, {
    ok: true,
    limits: relay.result.limits || {},
    observedAt: new Date().toISOString()
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/chat", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ultraRouter = require(`${__hooks}/wesi_ai_ultra_router.js`);
  const emotionEngine = require(`${__hooks}/wesi_ai_emotion_engine.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  const persona = String(body.persona || "").trim().toLowerCase();
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const lobbyMode = String(body.lobbyMode || "smart").trim().toLowerCase();
  const message = String(body.message || "").trim();
  const summary = String(body.summary || "").trim();
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
  const history = Array.isArray(body.messages) ? body.messages : [];
  const memory = body.memory && typeof body.memory === "object" ? body.memory : {};
  const currentEmotions = emotionEngine.sanitize(body.emotions);

  if (["zane", "nirvana", "lobby"].indexOf(persona) < 0) throw new BadRequestError("Некорректный режим Wesi AI");
  if (["fast", "pro", "maximum", "ultra"].indexOf(tier) < 0) throw new BadRequestError("Некорректный уровень Wesi AI");
  if (persona === "lobby" && ["both", "smart"].indexOf(lobbyMode) < 0) throw new BadRequestError("Некорректный режим лобби");
  if (!message || message.length > 32000) throw new BadRequestError("Некорректное сообщение Wesi AI");
  if (summary.length > 256000 || history.length > 900) throw new BadRequestError("Слишком большой контекст Wesi AI");
  if (body.provider != null || body.model != null || body.providerModel != null) throw new BadRequestError("Недоступная настройка Wesi AI");

  const personaBundle = personaRuntime.load(persona);
  if (!personaBundle.ready) return e.json(503, {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"});
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  let routePlan;
  if (tier === "ultra") {
    routePlan = ultraRouter.plan(message, cfg.routes.ultra);
  } else {
    const route = String(cfg.routes[tier] || "").trim();
    routePlan = {complexity: tier, candidates: route ? [{level: tier, route: route}] : []};
  }
  if (!routePlan.candidates.length) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  const cleanHistory = [];
  let historyChars = 0;
  for (const item of history) {
    if (!item || typeof item !== "object") continue;
    const author = String(item.author || item.role || "").toLowerCase();
    const text = String(item.text || item.content || "");
    if (["user", "zane", "nirvana", "tool"].indexOf(author) < 0) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение в контексте");
    historyChars += text.length;
    if (historyChars > 6000000) throw new BadRequestError("Слишком большой контекст Wesi AI");
    cleanHistory.push({author: author, text: text});
  }

  const emotionRequestId = "wai_emotion_" + Date.now() + "_" + $security.randomString(10);
  const emotionResult = emotionEngine.evaluate(
    ai,
    cfg,
    emotionRequestId,
    persona,
    message,
    cleanHistory,
    currentEmotions
  );
  const emotionalState = emotionResult.emotions;

  const cleanMemory = ai.sanitizeMemory(memory);
  const toolDefinitions = tools.definitions(e, ctx);
  const runtimeContext = tools.context(e, ctx, activeOrganizationId);
  const systemParts = [personaBundle.prompt];
  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\n" + cleanMemory.shared.join("\n"));
  const personaMemory = persona === "zane" ? cleanMemory.zane : persona === "nirvana" ? cleanMemory.nirvana : cleanMemory.zane.concat(cleanMemory.nirvana);
  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
  systemParts.push(
    "[WESI_AI_EMOTIONAL_STATE]\n" +
    JSON.stringify(emotionalState) + "\n" +
    "Эмоциональное состояние — внутренняя непрерывность персонажей. Оно должно мягко влиять на выбор слов, инициативу, юмор, дистанцию и реакцию, но не превращать ответ в театральную сцену. " +
    "Не перечисляй эмоции пользователю без причины. Не манипулируй чувством вины и не требуй эмоциональной заботы. " +
    "Незакрытые traces можно помнить между чатами; искренние извинения, время и позитивное взаимодействие должны естественно смягчать их. " +
    "Свежие факты и текущая просьба пользователя важнее старого эмоционального следа."
  );
  if (persona === "lobby") systemParts.push("[WESI_AI_LOBBY_MODE]\n" + lobbyMode);
  systemParts.push("[WESI_AI_RUNTIME_CONTEXT]\n" + JSON.stringify(runtimeContext));
  if (toolDefinitions.length) {
    systemParts.push(
      "[WESI_AI_TOOL_PROTOCOL]\n" +
      "Для реальных данных или действий WesiOS используй только инструменты ниже. " +
      "Чтобы вызвать инструмент, ответь ТОЛЬКО JSON без markdown: " +
      "{\"wesiTool\":{\"name\":\"tool_name\",\"arguments\":{}}}. " +
      "Никогда не утверждай, что действие выполнено, пока сервер не вернул verified result. " +
      "Если сервер вернул FORBIDDEN, объясни отказ в характере персоны и предложи допустимые alternatives.\n" +
      JSON.stringify(toolDefinitions)
    );
  }

  const requestId = "wai_" + Date.now() + "_" + $security.randomString(12);
  let stickyCandidate = 0;
  let effectiveRoute = routePlan.candidates[0];
  let contextMeta = null;
  const relayCall = function(system, phase) {
    let last = null;
    for (let index = stickyCandidate; index < routePlan.candidates.length; index++) {
      const candidate = routePlan.candidates[index];
      const relayRequestId = requestId + "_" + phase + "_" + candidate.level;
      const payload = {
        requestId: relayRequestId,
        route: candidate.route,
        operation: persona === "lobby" ? "lobby" : "chat",
        input: {system: system, history: cleanHistory, message: message}
      };
      const generated = ai.callRelay(cfg, payload, relayRequestId);
      if (generated.ok) {
        stickyCandidate = index;
        effectiveRoute = candidate;
        contextMeta = generated.context || contextMeta;
        return generated;
      }
      last = generated;
      if (tier !== "ultra" || !ultraRouter.shouldFallback(generated)) return generated;
    }
    return last || {ok: false, status: 503, code: "WAI_PROVIDER_UNAVAILABLE"};
  };

  const routeMeta = function() {
    const route = String(effectiveRoute && effectiveRoute.route || "");
    const slash = route.indexOf("/");
    return {
      requestedTier: tier,
      complexity: routePlan.complexity,
      effectiveLevel: String(effectiveRoute && effectiveRoute.level || tier),
      provider: slash > 0 ? route.slice(0, slash) : "",
      model: slash > 0 ? route.slice(slash + 1) : route,
      fallbackDepth: stickyCandidate,
      context: contextMeta
    };
  };

  const parseToolRequest = function(answer) {
    let text = String(answer || "").trim();
    if (text.indexOf("```json") === 0 && text.lastIndexOf("```") > 6) text = text.slice(7, text.lastIndexOf("```")).trim();
    else if (text.indexOf("```") === 0 && text.lastIndexOf("```") > 3) text = text.slice(3, text.lastIndexOf("```")).trim();
    try {
      const parsed = JSON.parse(text);
      const req = parsed && parsed.wesiTool && typeof parsed.wesiTool === "object" ? parsed.wesiTool : null;
      if (!req) return null;
      const name = String(req.name || "").trim();
      const args = req.arguments && typeof req.arguments === "object" ? req.arguments : {};
      if (!name) return null;
      return {name: name, arguments: args};
    } catch (_) { return null; }
  };

  const toolResults = [];
  const seenCalls = {};
  for (let turn = 0; turn < 4; turn++) {
    const currentSystem = systemParts.concat(toolResults.length ? ["[WESI_AI_VERIFIED_TOOL_RESULTS]\n" + JSON.stringify(toolResults)] : []).join("\n\n");
    const generated = relayCall(currentSystem, String(turn + 1));
    if (!generated.ok) return e.json(generated.status, {ok: false, code: generated.code, requestId: requestId});
    const toolRequest = toolDefinitions.length ? parseToolRequest(generated.answer) : null;
    if (!toolRequest) {
      return e.json(200, {ok: true, requestId: requestId, persona: persona, tier: tier, route: routeMeta(), answer: generated.answer, toolResults: toolResults, emotions: emotionalState});
    }

    const allowedTool = toolDefinitions.some((item) => String(item.name || "") === toolRequest.name);
    if (!allowedTool) {
      toolResults.push({tool: toolRequest.name, verified: true, ok: false, code: "FORBIDDEN", message: "Инструмент недоступен текущему сотруднику"});
      continue;
    }
    const signature = toolRequest.name + "|" + JSON.stringify(toolRequest.arguments);
    if (seenCalls[signature]) {
      toolResults.push({tool: toolRequest.name, verified: true, ok: false, code: "DUPLICATE_TOOL_CALL", message: "Повторный вызов не выполнен"});
      continue;
    }
    seenCalls[signature] = true;
    const executed = tools.execute(e, ctx, toolRequest.name, toolRequest.arguments, runtimeContext.activeOrganizationId);
    toolResults.push({tool: toolRequest.name, verified: true, ok: executed.ok === true, code: executed.code || null, message: executed.message || null, alternatives: executed.alternatives || null, result: executed.result || null});
  }

  const finalSystem = systemParts.concat([
    "[WESI_AI_VERIFIED_TOOL_RESULTS]\n" + JSON.stringify(toolResults),
    "[WESI_AI_FINAL_RESPONSE]\nЛимит инструментов исчерпан. Не вызывай инструменты снова. Дай пользователю итоговый ответ только по verified results и явно сообщи о неуспешных действиях."
  ]).join("\n\n");
  const finalGenerated = relayCall(finalSystem, "final");
  if (!finalGenerated.ok) return e.json(finalGenerated.status, {ok: false, code: finalGenerated.code, requestId: requestId});
  return e.json(200, {ok: true, requestId: requestId, persona: persona, tier: tier, route: routeMeta(), answer: finalGenerated.answer, toolResults: toolResults, emotions: emotionalState});
}, $apis.requireAuth("users"));
