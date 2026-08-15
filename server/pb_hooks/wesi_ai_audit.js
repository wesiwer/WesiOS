function clean(value, max) {
  const text = String(value == null ? "" : value);
  return text.length <= max ? text : text.slice(0, max);
}

module.exports = {
  record: function(e, ctx, entry) {
    if (typeof __hooks === "undefined") return false;
    try {
      const now = new Date().toISOString();
      const id = "critical_audit_wesi_ai_" + Date.now() + "_" + $security.randomString(8);
      const organizationId = clean(entry.organizationId || "org_wesi_inc", 180);
      const payload = {
        id: id,
        event: "wesi_ai_tool",
        entityType: clean(entry.entityType || "wesi_ai_action", 120),
        entityId: clean(entry.entityId || entry.tool || "unknown", 180),
        organizationId: organizationId,
        actorId: clean(ctx.employeeId || "system", 180),
        timestamp: now,
        source: "wesi_ai",
        reason: entry.code ? clean(entry.code, 120) : null,
        after: {
          tool: clean(entry.tool || "", 120),
          module: clean(entry.module || "", 80),
          action: clean(entry.action || "", 80),
          risk: clean(entry.risk || "", 24),
          policyDecision: clean(entry.policyDecision || "", 120),
          confirmationId: entry.confirmationId == null ? null : clean(entry.confirmationId, 180),
          persona: clean(entry.persona || "", 40),
          conversationId: clean(entry.conversationId || "", 180),
          requestId: clean(entry.requestId || "", 180),
          ok: entry.ok === true,
          targetEmployeeId: entry.targetEmployeeId == null ? null : clean(entry.targetEmployeeId, 180),
        },
      };
      const collection = e.app.findCollectionByNameOrId("wesios_records");
      const record = new Record(collection);
      record.set("owner", ctx.ownerId);
      record.set("org", "wesi-inc");
      record.set("coll", "critical_audit");
      record.set("rid", id);
      record.set("payload", payload);
      record.set("stamp", now);
      record.set("deleted", false);
      e.app.save(record);
      return true;
    } catch (_) {
      return false;
    }
  }
};
