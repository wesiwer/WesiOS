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
      return {ready: /^https:\/\//.test(url) && sharedSecret.length >= 32, url: url, sharedSecret: sharedSecret, routes: {fast: String(routes.fast || ""), pro: String(routes.pro || ""), maximum: String(routes.maximum || "")}};
    } catch (_) { return {ready: false, url: "", sharedSecret: "", routes: {fast: "", pro: "", maximum: ""}}; }
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
