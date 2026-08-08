/// Non-secret readiness check for WesiOS email OTP delivery.
/// It deliberately exposes no SMTP host, username, password or sender value.
routerAdd("GET", "/api/wesi/auth/mail-ready", (e) => {
  const settings = e.app.settings();
  const senderConfigured = Boolean(
    settings && settings.meta && String(settings.meta.senderAddress || "").trim(),
  );
  const smtpEnabled = Boolean(
    settings && settings.smtp && settings.smtp.enabled === true,
  );
  return e.json(senderConfigured ? 200 : 503, {
    "senderConfigured": senderConfigured,
    "smtpEnabled": smtpEnabled,
  });
});
