function text(value, max) {
  const raw = String(value == null ? "" : value).trim();
  return raw.length <= max ? raw : raw.slice(0, max);
}

module.exports = {
  evaluate: function(capability, invocation) {
    if (!capability) {
      return {allowed: false, decision: "deny_unregistered", code: "FORBIDDEN", message: "Инструмент не зарегистрирован в Capability Registry"};
    }
    const risk = String(capability.risk || "READ");
    if (risk === "READ") {
      return {allowed: true, decision: "allow_read", confirmationRequired: false};
    }
    if (risk === "WRITE") {
      return {allowed: true, decision: "allow_write_after_fresh_permission_check", confirmationRequired: false};
    }
    if (risk === "DESTRUCTIVE") {
      if (invocation && invocation.confirmedByTicket === true) {
        return {allowed: true, decision: "allow_confirmed_destructive", confirmationRequired: true};
      }
      return {
        allowed: false,
        decision: "require_confirmation",
        code: "CONFIRMATION_REQUIRED",
        message: "Это действие требует явного подтверждения в WesiOS",
        confirmationRequired: true,
      };
    }
    return {allowed: false, decision: "deny_unknown_risk", code: "FORBIDDEN", message: "Неизвестный класс риска Wesi AI"};
  },

  preview: function(capability, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    const target = text(input.id || input.taskId || input.eventId || input.articleId || input.clientId || input.dealId || input.transactionId || "", 180);
    return {
      tool: text(name, 120),
      module: text(capability && capability.module, 80),
      action: text(capability && capability.action, 80),
      risk: text(capability && capability.risk, 24),
      targetId: target || null,
    };
  },
};
