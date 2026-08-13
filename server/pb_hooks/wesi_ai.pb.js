/// Wesi AI main-server API foundation.
///
/// Product logic lives here on the main Wesi server. The foreign server is a
/// transport-only Relay and never receives employee credentials, grants or
/// direct WesiOS business-data access.

routerAdd("GET", "/api/wesi/ai/capabilities", (e) => {
  const ctx = resolveWesiAiIdentity(e);
  requireAiModule(ctx);
  return e.json(200, {
    "product": "Wesi AI",
    "tiers": ["fast", "pro", "maximum"],
    "personas": ["zane", "nirvana", "lobby"],
    "lobbyModes": ["both", "smart"],
    "features": {
      "localFirstChats": true,
      "streaming": false,
      "handoff": true,
      "lobby": true,
      "media": false,
      "wesiTools": false
    }
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/chat", (e) => {
  const ctx = resolveWesiAiIdentity(e);
  requireAiModule(ctx);

  const body = e.requestInfo().body || {};
  const persona = String(body.persona || "").trim().toLowerCase();
  const tier = String(body.tier || "fast").trim().toLowerCase();
  const conversationId = String(body.conversationId || "").trim();
  const lobbyMode = String(body.lobbyMode || "smart").trim().toLowerCase();
  const currentMessage = String(body.message || "").trim();
  const summary = String(body.summary || "").trim();
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const memory = body.memory && typeof body.memory === "object" ? body.memory : {};

  if (["zane", "nirvana", "lobby"].indexOf(persona) < 0) {
    throw new BadRequestError("Некорректный режим Wesi AI");
  }
  if (["fast", "pro", "maximum"].indexOf(tier) < 0) {
    throw new BadRequestError("Некорректный уровень Wesi AI");
  }
  if (persona === "lobby" && ["both", "smart"].indexOf(lobbyMode) < 0) {
    throw new BadRequestError("Некорректный режим лобби");
  }
  if (!currentMessage || currentMessage.length > 32000) {
    throw new BadRequestError("Некорректное сообщение Wesi AI");
  }
  if (conversationId.length > 160 || summary.length > 64000 || messages.length > 100) {
    throw new BadRequestError("Слишком большой контекст Wesi AI");
  }
  // Public API intentionally rejects provider/model selection. Employees only
  // select Wesi AI Fast/Pro/Maximum; provider routing remains server-internal.
  if (body.provider != null || body.model != null || body.providerModel != null) {
    throw new BadRequestError("Внешняя модель не является пользовательской настройкой Wesi AI");
  }

  const normalizedMessages = [];
  for (const item of messages) {
    if (!item || typeof item !== "object") continue;
    const role = String(item.role || item.author || "").trim().toLowerCase();
    const text = String(item.text || item.content || "");
    if (["user", "zane", "nirvana", "system", "tool"].indexOf(role) < 0) continue;
    if (text.length > 32000) throw new BadRequestError("Слишком длинное сообщение в контексте");
    normalizedMessages.push({"role": role, "text": text});
  }

  const cfg = readRelayConfig();
  if (!cfg.ready) {
    return e.json(503, {
      "ok": false,
      "code": "WAI_RELAY_NOT_CONFIGURED",
      "message": "Wesi AI Relay ещё не настроен на основном сервере"
    });
  }

  const requestId = "wai_" + Date.now() + "_" + $security.randomString(12);
  const requestPayload = {
    "requestId": requestId,
    "operation": "chat",
    "tier": tier,
    "payload": {
      "persona": persona,
      "lobbyMode": persona === "lobby" ? lobbyMode : null,
      "conversationId": conversationId,
      "summary": summary,
      "memory": sanitizeMemory(memory),
      "messages": normalizedMessages,
      "message": currentMessage
    }
  };

  const raw = JSON.stringify(requestPayload);
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = $security.hs256(timestamp + "." + raw, cfg.sharedSecret);

  let relayResponse;
  try {
    relayResponse = $http.send({
      "url": cfg.url.replace(/\/$/, "") + "/v1/wesi-ai",
      "method": "POST",
      "body": raw,
      "headers": {
        "Content-Type": "application/json",
        "X-Wesi-Request-Id": requestId,
        "X-Wesi-Timestamp": timestamp,
        "X-Wesi-Signature": signature
      },
      "timeout": 120
    });
  } catch (_) {
    return e.json(503, {"ok": false, "code": "WAI_RELAY_UNAVAILABLE"});
  }

  if (!relayResponse || relayResponse.statusCode < 200 || relayResponse.statusCode >= 300) {
    return e.json(502, {
      "ok": false,
      "code": "WAI_RELAY_BAD_RESPONSE",
      "requestId": requestId
    });
  }

  const result = relayResponse.json && typeof relayResponse.json === "object"
    ? relayResponse.json : {};
  const answer = String(result.answer || result.text || "").trim();
  if (!answer) {
    return e.json(502, {"ok": false, "code": "WAI_EMPTY_RESPONSE", "requestId": requestId});
  }

  // Never echo Relay/provider metadata to employee-facing API.
  return e.json(200, {
    "ok": true,
    "requestId": requestId,
    "persona": persona,
    "tier": tier,
    "answer": answer,
    "handoff": result.handoff && typeof result.handoff === "object" ? result.handoff : null,
    "lobby": result.lobby && typeof result.lobby === "object" ? result.lobby : null
  });
}, $apis.requireAuth("users"));

function resolveWesiAiIdentity(e) {
  if (!e.auth || e.hasSuperuserAuth()) {
    if (e.hasSuperuserAuth()) return {"isOwner": true, "employeeId": "owner", "modules": ["ai"]};
    throw new UnauthorizedError("Требуется вход WesiOS");
  }

  const payloadOf = (record) => {
    if (!record) return {};
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };

  const sid = String(e.request.header.get("X-WesiOS-Session") || "").trim();
  if (!/^[A-Za-z0-9_-]{24,96}$/.test(sid)) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }
  let session = null;
  try {
    session = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false",
      {"rid": "session:" + sid}
    );
  } catch (_) { session = null; }
  if (!session) throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");

  const sessionPayload = payloadOf(session);
  const expiresAt = Date.parse(String(sessionPayload.expiresAt || ""));
  if (String(sessionPayload.userId || "") !== e.auth.id || String(sessionPayload.revokedAt || "") ||
      !Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }

  let ownerMarker = null;
  try {
    ownerMarker = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false",
      {"owner": e.auth.id}
    );
  } catch (_) { ownerMarker = null; }
  if (ownerMarker) return {"isOwner": true, "employeeId": "owner", "modules": ["ai"]};

  let link = null;
  try {
    link = e.app.findFirstRecordByFilter(
      "wesios_records", "coll='system' && rid={:rid} && deleted=false",
      {"rid": "portal-account:" + e.auth.id}
    );
  } catch (_) { link = null; }
  if (!link) throw new ForbiddenError("Учётная запись не привязана к сотруднику WesiOS");
  const linkPayload = payloadOf(link);
  const ownerId = link.getString("owner");
  const employeeId = String(linkPayload.employeeId || "");
  if (!ownerId || !employeeId) throw new ForbiddenError("Привязка сотрудника повреждена");

  let employee = null;
  try {
    employee = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
      {"owner": ownerId, "rid": employeeId}
    );
  } catch (_) { employee = null; }
  const snapshot = employee ? payloadOf(employee) :
    (linkPayload.snapshot && typeof linkPayload.snapshot === "object" ? linkPayload.snapshot : linkPayload);
  const permissions = snapshot.permissions && typeof snapshot.permissions === "object" ? snapshot.permissions : {};
  return {
    "isOwner": false,
    "ownerId": ownerId,
    "employeeId": employeeId,
    "modules": Array.isArray(permissions.modules) ? permissions.modules.map(String) : []
  };
}

function requireAiModule(ctx) {
  if (!ctx || (!ctx.isOwner && ctx.modules.indexOf("ai") < 0)) {
    throw new ForbiddenError("Нет доступа к Wesi AI");
  }
}

function readRelayConfig() {
  try {
    const raw = $os.readFile(__hooks + "/.wesi-ai-relay.json");
    const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
    const cfg = JSON.parse(text || "{}");
    const url = String(cfg.url || "").trim();
    const sharedSecret = String(cfg.sharedSecret || "").trim();
    return {"ready": /^https:\/\//.test(url) && sharedSecret.length >= 32, "url": url, "sharedSecret": sharedSecret};
  } catch (_) {
    return {"ready": false, "url": "", "sharedSecret": ""};
  }
}

function sanitizeMemory(memory) {
  const result = {"shared": [], "zane": [], "nirvana": []};
  for (const key of ["shared", "zane", "nirvana"]) {
    const values = Array.isArray(memory[key]) ? memory[key] : [];
    result[key] = values.slice(0, 80).map((v) => String(v).slice(0, 4000));
  }
  return result;
}
