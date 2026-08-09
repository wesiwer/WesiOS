/// One-time, hash-gated owner recovery middleware.
///
/// This source never contains the recovery password or code. The temporary
/// password is high-entropy and ends with `-NNNNNN`; only its salted SHA-256
/// digest is committed. After a valid password starts the flow, the six-digit
/// suffix becomes a normal, single-use WesiOS OTP challenge.
///
/// The activation workflow substitutes the expiry placeholder immediately
/// before deploying this middleware together with wesi_auth_bootstrap.pb.js.
/// A clean bootstrap is deployed again after the owner confirms access.

const wesiOneTimeOwnerRecovery = {
  "id": "cee2b8b894a9978f",
  "login": "owner-recovery",
  "userId": "ex7bwkwp9e1l62o",
  "passwordSalt": "098fd01f9c169af77c2c216d91cca64a",
  "passwordHash": "7889bbd800cd2ae9e5c1ee3d82c85043434f4583c8d59a3063fc1fb3e1083b6b",
  "expiresAt": "__WESI_RECOVERY_EXPIRES_AT__",
};

routerUse((e) => {
  const path = String(e.request.url.path || "");
  const method = String(e.request.method || "GET").toUpperCase();
  if (method !== "POST" || path !== "/api/wesi/auth/start-v2") {
    return e.next();
  }

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const login = String(body.login || "").trim().toLowerCase();
  if (login !== wesiOneTimeOwnerRecovery.login) return e.next();

  const activationExpiresAt = Date.parse(wesiOneTimeOwnerRecovery.expiresAt);
  if (!Number.isFinite(activationExpiresAt) || activationExpiresAt <= Date.now()) {
    throw new UnauthorizedError("Временный вход владельца недействителен");
  }

  const password = String(body.password || "");
  const passwordHash = $security.sha256(
    wesiOneTimeOwnerRecovery.passwordSalt + ":" + password,
  );
  const codeMatch = password.match(/-(\d{6})$/);
  if (!codeMatch || passwordHash !== wesiOneTimeOwnerRecovery.passwordHash) {
    throw new UnauthorizedError("Неверный логин или пароль");
  }
  const code = codeMatch[1];

  let user = null;
  try {
    user = e.app.findRecordById("users", wesiOneTimeOwnerRecovery.userId);
  } catch (_) {
    user = null;
  }
  if (!user) throw new ForbiddenError("Профиль владельца закрыт");

  try {
    e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + user.id + "' && coll='system' && rid='portal-owner' && deleted=false",
    );
  } catch (_) {
    throw new ForbiddenError("Временный вход доступен только владельцу");
  }

  const valueObject = (record) => {
    try {
      const raw = record.get("payload");
      return raw && typeof raw === "object" ? raw : {};
    } catch (_) {
      return {};
    }
  };
  const stateRid = "recovery:" + wesiOneTimeOwnerRecovery.id;
  let state = null;
  try {
    state = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid='" + stateRid + "' && deleted=false",
    );
  } catch (_) {
    state = null;
  }

  if (state) {
    const statePayload = valueObject(state);
    const existingId = String(statePayload.challengeId || "");
    let existing = null;
    if (/^[A-Za-z0-9]{40}$/.test(existingId)) {
      try {
        existing = e.app.findFirstRecordByFilter(
          "wesios_records",
          "owner='__wesios_security__' && coll='security' && rid='otp:" + existingId + "' && deleted=false",
        );
      } catch (_) {
        existing = null;
      }
    }
    const existingPayload = existing ? valueObject(existing) : {};
    const existingExpiresAt = Date.parse(String(existingPayload.expiresAt || ""));
    if (existing && Number.isFinite(existingExpiresAt) && existingExpiresAt > Date.now()) {
      return e.json(200, {
        "challengeId": existingId,
        "maskedEmail": "одноразовый защищённый канал",
        "emailSetupRequired": false,
        "expiresInSeconds": Math.max(1, Math.floor((existingExpiresAt - Date.now()) / 1000)),
        "recovery": true,
      });
    }
    throw new UnauthorizedError("Временный вход владельца уже использован");
  }

  const challengeId = $security.randomStringWithAlphabet(
    40,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const challengeSalt = $security.randomStringWithAlphabet(
    32,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
  );
  const now = new Date();
  const challengeExpiresAt = new Date(
    Math.min(activationExpiresAt, now.getTime() + 10 * 60 * 1000),
  );
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
    "login": wesiOneTimeOwnerRecovery.login,
    "email": "",
    "purpose": body.purpose === "portal" ? "portal" : "app",
    "hash": $security.sha256(challengeId + ":" + challengeSalt + ":" + code),
    "salt": challengeSalt,
    "attempts": 0,
    "sentAt": now.toISOString(),
    "expiresAt": challengeExpiresAt.toISOString(),
    "delivery": "private-one-time-recovery",
    "recoveryId": wesiOneTimeOwnerRecovery.id,
  });
  challenge.set("stamp", now.toISOString());
  challenge.set("deleted", false);
  e.app.save(challenge);

  const recoveryState = new Record(collection);
  recoveryState.set("owner", "__wesios_security__");
  recoveryState.set("org", "wesi-inc");
  recoveryState.set("coll", "security");
  recoveryState.set("rid", stateRid);
  recoveryState.set("payload", {
    "kind": "owner-recovery",
    "recoveryId": wesiOneTimeOwnerRecovery.id,
    "challengeId": challengeId,
    "startedAt": now.toISOString(),
    "expiresAt": challengeExpiresAt.toISOString(),
  });
  recoveryState.set("stamp", now.toISOString());
  recoveryState.set("deleted", false);
  try {
    e.app.save(recoveryState);
  } catch (_) {
    challenge.set("deleted", true);
    challenge.set("stamp", new Date().toISOString());
    e.app.save(challenge);
    throw new InternalServerError("Не удалось создать одноразовый вход владельца");
  }

  return e.json(200, {
    "challengeId": challengeId,
    "maskedEmail": "одноразовый защищённый канал",
    "emailSetupRequired": false,
    "expiresInSeconds": Math.max(1, Math.floor((challengeExpiresAt.getTime() - Date.now()) / 1000)),
    "recovery": true,
  });
});
