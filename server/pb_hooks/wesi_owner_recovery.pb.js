/// Temporary, root-gated owner recovery bridge.
///
/// This hook does NOT disable normal WesiOS 2FA. It only handles
/// POST /api/wesi/auth/start-v2 for login `WesiOff` when a short-lived,
/// root-created /opt/pocketbase/pb_hooks/.wesi-owner-recovery.json exists.
/// The recovery file is consumed immediately after a normal OTP challenge is
/// created. The existing /api/wesi/auth/verify endpoint then validates the
/// six-digit code and issues the standard revocable WesiOS session.

routerUse((e) => {
  const path = String(e.request.url.path || "");
  const method = String(e.request.method || "GET").toUpperCase();
  if (method !== "POST" || path !== "/api/wesi/auth/start-v2") {
    return e.next();
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const login = String(body.login || "").trim().toLowerCase();
  if (login !== "wesioff") return e.next();

  const recoveryPath = __hooks + "/.wesi-owner-recovery.json";
  let recovery = null;
  try {
    const raw = $os.readFile(recoveryPath);
    const text = typeof raw === "string"
      ? raw
      : String.fromCharCode.apply(null, raw || []);
    recovery = JSON.parse(text || "{}");
  } catch (_) {
    return e.next();
  }

  const userId = String(recovery.userId || "").trim();
  const code = String(recovery.code || "").trim();
  const expiresAt = Date.parse(String(recovery.expiresAt || ""));
  if (!/^[A-Za-z0-9_-]{10,40}$/.test(userId) ||
      !/^\d{6}$/.test(code) ||
      !Number.isFinite(expiresAt) ||
      expiresAt <= Date.now() ||
      expiresAt - Date.now() > 15 * 60 * 1000) {
    throw new UnauthorizedError("Временное восстановление входа недействительно");
  }

  let user = null;
  try { user = e.app.findRecordById("users", userId); } catch (_) { user = null; }
  const password = String(body.password || "");
  if (!user || !password || !user.validatePassword(password)) {
    throw new UnauthorizedError("Неверный логин или пароль");
  }

  // Recovery is owner-only. A copied recovery file cannot be used for an
  // arbitrary user record.
  try {
    e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + user.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) {
    throw new ForbiddenError("Временное восстановление доступно только владельцу");
  }

  let email = user.getString("email") || "";
  try {
    const ownerRecord = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + user.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
    const payload = ownerRecord.get("payload") || {};
    const candidate = String(payload.email || "").trim().toLowerCase();
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate) && !candidate.endsWith("@wesi.local")) {
      email = candidate;
    }
  } catch (_) {}

  const challengeId = $security.randomStringWithAlphabet(
    40,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const salt = $security.randomStringWithAlphabet(
    32,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const now = new Date();
  const challengeExpires = new Date(Math.min(expiresAt, now.getTime() + 10 * 60 * 1000));
  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const challenge = new Record(collection);
  challenge.set("owner", "__wesios_security__");
  challenge.set("org", "wesi-inc");
  challenge.set("coll", "security");
  challenge.set("rid", "otp:" + challengeId);
  challenge.set("payload", {
    "kind": "otp",
    "challengeId": challengeId,
    "userId": user.id,
    "employeeId": "owner",
    "login": "wesioff",
    "email": email,
    "purpose": body.purpose === "portal" ? "portal" : "app",
    "hash": $security.sha256(challengeId + ":" + salt + ":" + code),
    "salt": salt,
    "attempts": 0,
    "sentAt": now.toISOString(),
    "expiresAt": challengeExpires.toISOString(),
    "delivery": "root-recovery",
  });
  challenge.set("stamp", now.toISOString());
  challenge.set("deleted", false);
  e.app.save(challenge);

  // Consume before returning. A second /start-v2 request cannot reuse it.
  try { $os.remove(recoveryPath); } catch (_) {
    // If the runtime cannot unlink the file, invalidate its contents instead.
    try { $os.writeFile(recoveryPath, "{}", 0600); } catch (_) {}
  }

  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": "временный recovery-код",
    "emailSetupRequired": false,
    "expiresInSeconds": Math.max(1, Math.floor((challengeExpires.getTime() - Date.now()) / 1000)),
    "recovery": true,
  });
});
