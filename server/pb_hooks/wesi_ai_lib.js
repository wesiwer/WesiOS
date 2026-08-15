module.exports = {
  resolveIdentity: function(e) {
    if (!e.auth || e.hasSuperuserAuth()) {
      if (e.hasSuperuserAuth()) return {isOwner: true, ownerId: e.auth.id, employeeId: "owner", modules: ["ai"]};
      throw new UnauthorizedError("Требуется вход WesiOS");
    }
    const payloadOf = function(record) {
      if (!record) return {};
      try {
        const raw = record.get("payload");
        if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
        if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
      } catch (_) {}
      return {};
    };
    const sessionPayloadOf = function(record) {
      if (!record) return {};
      try {
        const model = new DynamicModel({userId: "", expiresAt: "", revokedAt: ""});
        record.unmarshalJSONField("payload", model);
        return {userId: String(model.userId || ""), expiresAt: String(model.expiresAt || ""), revokedAt: String(model.revokedAt || "")};
      } catch (_) { return {}; }
    };
    const sid = String(e.request.header.get("X-WesiOS-Session") || "").trim();
    if (!/^[A-Za-z0-9_-]{24,96}$/.test(sid)) throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
    let session = null;
    try {
      session = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false", {rid: "session:" + sid});
    } catch (_) { session = null; }
    if (!session) throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
    const sp = sessionPayloadOf(session);
    const exp = Date.parse(String(sp.expiresAt || ""));
    if (String(sp.userId || "") !== e.auth.id || String(sp.revokedAt || "") || !Number.isFinite(exp) || exp <= Date.now()) {
      throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
    }
    let ownerMarker = null;
    try {
      ownerMarker = e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false", {owner: e.auth.id});
    } catch (_) { ownerMarker = null; }
    if (ownerMarker) return {isOwner: true, ownerId: e.auth.id, employeeId: "owner", modules: ["ai"]};
    let link = null;
    try {
      link = e.app.findFirstRecordByFilter("wesios_records", "coll='system' && rid={:rid} && deleted=false", {rid: "portal-account:" + e.auth.id});
    } catch (_) { link = null; }
    if (!link) throw new ForbiddenError("Учётная запись не привязана к сотруднику WesiOS");
    const lp = payloadOf(link);
    const ownerId = link.getString("owner");
    const employeeId = String(lp.employeeId || "");
    if (!ownerId || !employeeId) throw new ForbiddenError("Привязка сотрудника повреждена");
    let employee = null;
    try {
      employee = e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false", {owner: ownerId, rid: employeeId});
    } catch (_) { employee = null; }
    const snapshot = employee ? payloadOf(employee) : (lp.snapshot && typeof lp.snapshot === "object" ? lp.snapshot : lp);
    const permissions = snapshot.permissions && typeof snapshot.permissions === "object" ? snapshot.permissions : {};
    return {isOwner: false, ownerId: ownerId, employeeId: employeeId, modules: Array.isArray(permissions.modules) ? permissions.modules.map(String) : []};
  },

  requireAiModule: function(ctx) {
    if (!ctx || (!ctx.isOwner && ctx.modules.indexOf("ai") < 0)) throw new ForbiddenError("Нет доступа к Wesi AI");
  },

  readRelayConfig: function() {
    try {
      const raw = $os.readFile(__hooks + "/.wesi-ai-relay.json");
      const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
      const cfg = JSON.parse(text || "{}");
      const url = String(cfg.url || "").trim();
      const sharedSecret = String(cfg.sharedSecret || "").trim();
      const routes = cfg.routes && typeof cfg.routes === "object" ? cfg.routes : {};
      const streamSecret = String(cfg.streamSecret || "").trim();
      return {
        ready: /^https:\/\//.test(url) && sharedSecret.length >= 32,
        url: url,
        sharedSecret: sharedSecret,
        streamSecret: streamSecret,
        routes: {
          fast: String(routes.fast || ""),
          pro: String(routes.pro || ""),
          maximum: String(routes.maximum || "")
        }
      };
    } catch (_) {
      return {ready: false, url: "", sharedSecret: "", streamSecret: "", routes: {fast: "", pro: "", maximum: ""}};
    }
  },

  callRelayJson: function(cfg, payload, requestId, timeoutSeconds) {
    const raw = JSON.stringify(payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = $security.hs256(requestId + "." + timestamp + "." + raw, cfg.sharedSecret);
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
          "X-Wesi-Signature": signature
        },
        timeout: Math.max(10, Math.min(Number(timeoutSeconds || 120), 420))
      });
    } catch (_) {
      return {ok: false, status: 503, code: "WAI_RELAY_UNAVAILABLE"};
    }
    const result = relay && relay.json && typeof relay.json === "object" ? relay.json : {};
    if (!relay || relay.statusCode < 200 || relay.statusCode >= 300 || result.ok !== true) {
      const status = relay && relay.statusCode === 429 ? 429 : (relay && relay.statusCode >= 400 && relay.statusCode < 500 ? relay.statusCode : 502);
      return {ok: false, status: status, code: String(result.code || "WAI_RELAY_BAD_RESPONSE")};
    }
    return {ok: true, result: result};
  },

  callRelay: function(cfg, payload, requestId) {
    const relay = module.exports.callRelayJson(cfg, payload, requestId, 120);
    if (!relay.ok) return relay;
    const answer = String(relay.result.answer || "").trim();
    return answer ? {ok: true, answer: answer} : {ok: false, status: 502, code: "WAI_EMPTY_RESPONSE"};
  },

  fetchRelayArtifact: function(cfg, artifactId) {
    const id = String(artifactId || "").trim();
    if (!/^[A-Za-z0-9_-]{20,80}$/.test(id)) return {ok: false, status: 400, code: "WAI_RELAY_BAD_ARTIFACT"};
    const requestId = "wai_art_" + Date.now() + "_" + $security.randomString(12);
    const payload = {requestId: requestId, artifactId: id};
    const raw = JSON.stringify(payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = $security.hs256(requestId + "." + timestamp + "." + raw, cfg.sharedSecret);
    let relay;
    try {
      relay = $http.send({
        url: cfg.url.replace(/\/$/, "") + "/v1/wesi-ai-artifact",
        method: "POST",
        body: raw,
        headers: {
          "Content-Type": "application/json",
          "X-Wesi-Request-Id": requestId,
          "X-Wesi-Timestamp": timestamp,
          "X-Wesi-Signature": signature
        },
        timeout: 180
      });
    } catch (_) {
      return {ok: false, status: 503, code: "WAI_RELAY_UNAVAILABLE"};
    }
    if (!relay || relay.statusCode < 200 || relay.statusCode >= 300 || !Array.isArray(relay.body)) {
      const result = relay && relay.json && typeof relay.json === "object" ? relay.json : {};
      return {ok: false, status: 502, code: String(result.code || "WAI_RELAY_ARTIFACT_FAILED")};
    }
    if (!relay.body.length || relay.body.length > 128 * 1024 * 1024) {
      return {ok: false, status: 502, code: "WAI_RELAY_ARTIFACT_TOO_LARGE"};
    }
    let mimeType = "application/octet-stream";
    let kind = "media";
    const headers = relay.headers && typeof relay.headers === "object" ? relay.headers : {};
    for (const key of Object.keys(headers)) {
      const value = Array.isArray(headers[key]) ? headers[key][0] : headers[key];
      if (String(key).toLowerCase() === "content-type") mimeType = String(value || mimeType).split(";")[0].trim();
      if (String(key).toLowerCase() === "x-wesi-media-kind") kind = String(value || kind).trim();
    }
    return {ok: true, bytes: relay.body, mimeType: mimeType, kind: kind};
  },

  sanitizeMemory: function(memory) {
    const result = {shared: [], zane: [], nirvana: []};
    for (const key of ["shared", "zane", "nirvana"]) {
      const values = Array.isArray(memory[key]) ? memory[key] : [];
      result[key] = values.slice(0, 80).map(function(v) { return String(v).slice(0, 4000); });
    }
    return result;
  }
};
