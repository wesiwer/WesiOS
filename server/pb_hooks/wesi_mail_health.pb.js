/// Non-secret readiness check for WesiOS email OTP delivery.
/// PocketBase uses configured SMTP or the local Unix sendmail command.
routerAdd("GET", "/api/wesi/auth/mail-ready", (e) => {
  const settings = e.app.settings();
  const senderConfigured = Boolean(
    settings && settings.meta && String(settings.meta.senderAddress || "").trim(),
  );
  const smtpEnabled = Boolean(
    settings && settings.smtp && settings.smtp.enabled === true,
  );
  const smtpHostConfigured = Boolean(
    settings && settings.smtp && String(settings.smtp.host || "").trim(),
  );
  const smtpReady = senderConfigured && smtpEnabled && smtpHostConfigured;
  // With SMTP disabled PocketBase intentionally falls back to the local
  // Unix sendmail command. CI verifies that binary on production over SSH.
  return e.json(senderConfigured ? 200 : 503, {
    "ready": senderConfigured,
    "senderConfigured": senderConfigured,
    "smtpEnabled": smtpEnabled,
    "smtpHostConfigured": smtpHostConfigured,
    "smtpReady": smtpReady,
    "transport": smtpReady ? "smtp" : "sendmail",
    "reason": senderConfigured ? "ok" : "sender_not_configured",
  });
});
