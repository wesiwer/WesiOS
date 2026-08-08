/// Non-secret readiness check for WesiOS OTP delivery.
/// Never exposes SMTP credentials, API keys or sender values.
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

  let httpsProviderConfigured = false;
  let httpsProvider = "";
  try {
    const raw = $os.readFile(__hooks + "/.wesi-mail.json");
    const text = typeof raw === "string"
      ? raw
      : String.fromCharCode.apply(null, raw || []);
    const cfg = JSON.parse(text || "{}");
    httpsProvider = String(cfg.provider || "").trim().toLowerCase();
    httpsProviderConfigured =
      httpsProvider === "resend" &&
      Boolean(String(cfg.apiKey || "").trim()) &&
      Boolean(String(cfg.from || "").trim());
  } catch (_) {}

  const smtpReady = senderConfigured && smtpEnabled && smtpHostConfigured;
  const ready = smtpReady || httpsProviderConfigured;
  return e.json(ready ? 200 : 503, {
    "ready": ready,
    "senderConfigured": senderConfigured,
    "smtpEnabled": smtpEnabled,
    "smtpHostConfigured": smtpHostConfigured,
    "smtpReady": smtpReady,
    "httpsProviderConfigured": httpsProviderConfigured,
    "httpsProvider": httpsProviderConfigured ? httpsProvider : "",
    "reason": ready
      ? "ok"
      : (senderConfigured ? "transport_not_configured" : "sender_not_configured"),
  });
});
