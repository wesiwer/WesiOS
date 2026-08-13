module.exports = {
  record: function(e, ctx, entry) {
    if (typeof __hooks === "undefined") return false;
    try {
      const now = new Date().toISOString();
      const id = "critical_audit_wesi_ai_" + Date.now() + "_" + $security.randomString(8);
      const organizationId = String(entry.organizationId || "org_wesi_inc");
      const payload = {
        id: id,
        event: "wesi_ai_tool",
        entityType: String(entry.entityType || "wesi_ai_action"),
        entityId: String(entry.entityId || entry.tool || "unknown"),
        organizationId: organizationId,
        actorId: String(ctx.employeeId || "system"),
        timestamp: now,
        source: "wesi_ai",
        reason: entry.code ? String(entry.code) : null,
        after: {
          tool: String(entry.tool || ""),
          persona: String(entry.persona || ""),
          conversationId: String(entry.conversationId || ""),
          requestId: String(entry.requestId || ""),
          ok: entry.ok === true,
          targetEmployeeId: entry.targetEmployeeId == null ? null : String(entry.targetEmployeeId),
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
