/// Temporary, root-gated owner recovery bridge.
///
/// This hook does NOT disable normal WesiOS 2FA. It only handles
/// POST /api/wesi/auth/start-v2 for login `WesiOff` when a short-lived,
/// root-created /opt/pocketbase/.wesi-owner-recovery.json exists.
/// The recovery flag is deliberately outside pb_hooks so creating/removing it
/// cannot trigger PocketBase hook autoreload between start-v2 and verify.

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

  const recoveryPath = "/opt/pocketbase/.wesi-owner-recovery.json";
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
  const recoveryExpiresIso = String(recovery.expiresAt || "").trim();
  const expiresAt = Date.parse(recoveryExpiresIso);
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

  // Recovery is owner-only. A copied recovery flag cannot be used for an
  // arbitrary user record.
  try {
    e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + user.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) {
    throw new ForbiddenError("Временное восстановление доступно только владельцу");
  }

  const challengeId = $security.randomStringWithAlphabet(
    40,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const salt = $security.randomStringWithAlphabet(
    32,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const now = new Date();
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
    "email": "",
    "purpose": body.purpose === "portal" ? "portal" : "app",
    "hash": $security.sha256(challengeId + ":" + salt + ":" + code),
    "salt": salt,
    "attempts": 0,
    "sentAt": now.toISOString(),
    "expiresAt": recoveryExpiresIso,
    "delivery": "root-recovery",
  });
  challenge.set("stamp", now.toISOString());
  challenge.set("deleted", false);
  e.app.save(challenge);

  // Consume before returning. Since the flag is outside pb_hooks, removing it
  // does not restart PocketBase.
  try { $os.remove(recoveryPath); } catch (_) {
    // Decimal 384 == 0600; strict-mode JS rejects legacy octal literals.
    try { $os.writeFile(recoveryPath, "{}", 384); } catch (_) {}
  }

  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": "временный recovery-код",
    "emailSetupRequired": false,
    "expiresInSeconds": Math.max(1, Math.floor((expiresAt - Date.now()) / 1000)),
    "recovery": true,
  });
});
