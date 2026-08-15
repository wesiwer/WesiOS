function streamSecret(e, ai) {
  const cfg = ai.readRelayConfig();
  const expected = String(cfg.streamSecret || "");
  const supplied = String(e.request.header.get("X-Wesi-AI-Stream-Secret") || "");
  if (!expected || expected.length < 32 || supplied !== expected) {
    throw new ForbiddenError("Wesi AI stream gateway is not trusted");
  }
  return cfg;
}

function cleanRequest(e, body, ctx, ai, personaRuntime, tools, cfg) {
  const persona = String(body.persona || "").trim().toLowerCase();
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const lobbyMode = String(body.lobbyMode || "smart").trim().toLowerCase();
  const message = String(body.message || "").trim();
  const summary = String(body.summary || "").trim();
  const conversationId = String(body.conversationId || "").trim();
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
  const history = Array.isArray(body.messages) ? body.messages : [];
  const memory = body.memory && typeof body.memory === "object" ? body.memory : {};
  const attachmentsRaw = Array.isArray(body.attachments) ? body.attachments : [];

  if (["zane", "nirvana"].indexOf(persona) < 0) {
    throw new BadRequestError("Streaming пока доступен только прямому чату Зейна/Нирваны");
  }
  if (["fast", "pro", "maximum"].indexOf(tier) < 0) {
    throw new BadRequestError("Некорректный уровень Wesi AI");
  }
  if (["both", "smart"].indexOf(lobbyMode) < 0) {
    throw new BadRequestError("Некорректный режим Wesi AI");
  }
  if ((!message && !attachmentsRaw.length) || message.length > 32000) {
    throw new BadRequestError("Некорректное сообщение Wesi AI");
  }
  if (summary.length > 64000 || history.length > 100 || conversationId.length > 160) {
    throw new BadRequestError("Слишком большой контекст Wesi AI");
  }
  if (body.provider != null || body.model != null || body.providerModel != null) {
    throw new BadRequestError("Недоступная настройка Wesi AI");
  }

  const cleanAttachments = [];
  let totalAttachmentBytes = 0;
  if (attachmentsRaw.length > 4) throw new BadRequestError("Слишком много вложений Wesi AI");
  for (const raw of attachmentsRaw) {
    if (!raw || typeof raw !== "object") throw new BadRequestError("Некорректное вложение Wesi AI");
    let name = String(raw.name || "file").replace(/[\\/\x00-\x1f\x7f]/g, "_").trim();
    if (!name) name = "file";
    if (name.length > 180) name = name.slice(name.length - 180);
    const mimeType = String(raw.mimeType || "application/octet-stream").trim().toLowerCase();
    if (!/^[a-z0-9!#$&^_.+\-]+\/[a-z0-9!#$&^_.+\-]+$/i.test(mimeType) || mimeType.length > 120) {
      throw new BadRequestError("Некорректный MIME вложения Wesi AI");
    }
    const dataBase64 = String(raw.dataBase64 || "").trim();
    if (!dataBase64 || dataBase64.length > 20971520 || !/^[A-Za-z0-9+/]*={0,2}$/.test(dataBase64) || dataBase64.length % 4 !== 0) {
      throw new BadRequestError("Некорректные данные вложения Wesi AI");
    }
    const padding = dataBase64.endsWith("==") ? 2 : dataBase64.endsWith("=") ? 1 : 0;
    const byteSize = Math.floor(dataBase64.length * 3 / 4) - padding;
    if (byteSize <= 0 || byteSize > 15728640) throw new BadRequestError("Вложение Wesi AI слишком большое");
    const declared = Number(raw.byteSize || 0);
    if (declared && declared !== byteSize) throw new BadRequestError("Размер вложения Wesi AI не совпадает");
    totalAttachmentBytes += byteSize;
    if (totalAttachmentBytes > 18874368) throw new BadRequestError("Суммарный размер вложений Wesi AI слишком большой");
    cleanAttachments.push({name: name, mimeType: mimeType, byteSize: byteSize, dataBase64: dataBase64});
  }

  const personaBundle = personaRuntime.load(persona);
  if (!personaBundle.ready) {
    return {status: 503, error: {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"}};
  }
  const route = cfg.routes[tier] || "";
  if (!cfg.ready || !route) {
    return {status: 503, error: {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"}};
  }

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
  const toolDefinitions = tools.definitions(e, ctx);
  const runtimeContext = tools.context(e, ctx, activeOrganizationId);
  const systemParts = [personaBundle.prompt];
  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\n" + cleanMemory.shared.join("\n"));
  const personaMemory = persona === "zane" ? cleanMemory.zane : cleanMemory.nirvana;
  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\n" + personaMemory.join("\n"));
  if (cleanMemory.project.length) systemParts.push("[WESI_AI_PROJECT_MEMORY]\n" + cleanMemory.project.join("\n"));
  if (cleanAttachments.length) {
    systemParts.push(
      "[WESI_AI_ATTACHMENTS]\n" +
      "Пользователь приложил файлы. Анализируй их содержимое как часть текущего запроса. " +
      "Не утверждай, что файл прочитан, если preprocessor сообщил, что бинарный формат не удалось достоверно декодировать."
    );
  }
  systemParts.push("[WESI_AI_RUNTIME_CONTEXT]\n" + JSON.stringify(runtimeContext));
  if (toolDefinitions.length) {
    systemParts.push(
      "[WESI_AI_TOOL_PROTOCOL]\n" +
      "Для реальных данных или действий WesiOS используй только инструменты ниже. " +
      "Чтобы вызвать инструмент, ответь ТОЛЬКО JSON без markdown: " +
      "{\"wesiTool\":{\"name\":\"tool_name\",\"arguments\":{}}}. " +
      "Никогда не утверждай, что действие выполнено, пока сервер не вернул verified result. " +
      "Если сервер вернул FORBIDDEN, объясни отказ и предложи допустимые alternatives.\n" +
      JSON.stringify(toolDefinitions)
    );
  }

  return {
    status: 200,
    prepared: {
      requestId: "wai_stream_" + Date.now() + "_" + $security.randomString(12),
      persona: persona,
      tier: tier,
      route: route,
      operation: "chat",
      systemParts: systemParts,
      history: cleanHistory,
      message: message || "Проанализируй приложенные файлы.",
      attachments: cleanAttachments,
      activeOrganizationId: String(runtimeContext.activeOrganizationId || activeOrganizationId || ""),
      conversationId: conversationId,
      toolNames: toolDefinitions.map(function(item) { return String(item.name || ""); }).filter(Boolean)
    }
  };
}

routerAdd("POST", "/api/wesi/ai/stream/prepare", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = streamSecret(e, ai);
  const result = cleanRequest(e, e.requestInfo().body || {}, ctx, ai, personaRuntime, tools, cfg);
  if (result.error) return e.json(result.status, result.error);
  return e.json(200, {ok: true, prepared: result.prepared});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/stream/tool", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  streamSecret(e, ai);
  const body = e.requestInfo().body || {};
  const name = String(body.name || "").trim();
  const args = body.arguments && typeof body.arguments === "object" ? body.arguments : {};
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
  const allowed = tools.definitions(e, ctx).some(function(item) {
    return String(item.name || "") === name;
  });
  if (!allowed) {
    return e.json(200, {
      ok: true,
      toolResult: {tool: name, verified: true, ok: false, code: "FORBIDDEN", message: "Инструмент недоступен текущему сотруднику"}
    });
  }
  const executed = tools.execute(e, ctx, name, args, activeOrganizationId);
  return e.json(200, {
    ok: true,
    toolResult: {
      tool: name,
      verified: true,
      ok: executed.ok === true,
      code: executed.code || null,
      message: executed.message || null,
      alternatives: executed.alternatives || null,
      result: executed.result || null
    }
  });
}, $apis.requireAuth("users"));
