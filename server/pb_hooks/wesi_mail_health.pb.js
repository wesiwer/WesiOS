/// Non-secret readiness check for WesiOS email OTP delivery.
/// A sender address alone is not enough: PocketBase needs an actual SMTP
/// transport. Production has no local sendmail/postfix fallback, so reporting
/// 200 while SMTP is disabled makes the login system look healthy even though
/// every OTP delivery will fail.
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
  const transportReady = smtpEnabled && smtpHostConfigured;
  const ready = senderConfigured && transportReady;

  return e.json(ready ? 200 : 503, {
    "ready": ready,
    "senderConfigured": senderConfigured,
    "transportReady": transportReady,
    "smtpEnabled": smtpEnabled,
    "reason": ready
      ? "ok"
      : !senderConfigured
        ? "sender_not_configured"
        : !smtpEnabled
          ? "smtp_disabled"
          : "smtp_host_not_configured",
  });
});
