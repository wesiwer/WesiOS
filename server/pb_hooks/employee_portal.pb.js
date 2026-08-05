/// Защищённые маршруты портала сотрудников WesiOS.
///
/// Источник истины для входа — auth-коллекция PocketBase `users`.
/// WesiOS создаёт или обновляет запись на сервере, а сайт только проверяет
/// введённые логин и пароль стандартным auth-with-password.

const PORTAL_ARTIFACTS_ROOT = $os.getenv("WESI_ARTIFACTS_DIR") ||
  "/opt/pocketbase/pb_public/artifacts";
const OWNER_MARKER_COLL = "system";
const OWNER_MARKER_RID = "portal-owner";

function portalReadText(fs, name) {
  const raw = fs.readFile(name);
  if (typeof raw === "string") return raw;
  return String.fromCharCode.apply(null, raw);
}

function portalManifest() {
  try {
    const fs = $os.dirFS(PORTAL_ARTIFACTS_ROOT);
    return JSON.parse(portalReadText(fs, "app/app-manifest.json"));
  } catch (error) {
    console.log("employee portal manifest error:", error);
    throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
  }
}

function portalSafePath(value) {
  if (typeof value !== "string" || value === "") {
    throw new NotFoundError("Файл сборки не указан");
  }
  const clean = $filepath.clean(value).replace(/\\/g, "/");
  if (!clean.startsWith("app/") || clean.indexOf("../") >= 0 || clean.startsWith("/")) {
    throw new ForbiddenError("Недопустимый путь сборки");
  }
  return clean;
}

function portalFileName(value, fallback) {
  if (typeof value !== "string" || value === "") return fallback;
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function portalLogin(login) {
  const normalized = String(login || "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
    throw new BadRequestError(
      "Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание",
    );
  }
  return normalized;
}

function portalLoginEmail(login) {
  return portalLogin(login) + "@wesi.local";
}

function portalOwnerMarker(app, ownerId) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner='" + ownerId + "' && coll='" + OWNER_MARKER_COLL +
        "' && rid='" + OWNER_MARKER_RID + "' && deleted=false",
    );
  } catch (_) {
    return null;
  }
}

function portalAnyOwnerMarker(app) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "coll='" + OWNER_MARKER_COLL + "' && rid='" +
        OWNER_MARKER_RID + "' && deleted=false",
    );
  } catch (_) {
    return null;
  }
}

/// Первый подтверждённый основной пользователь, который сохраняет свои
/// учётные данные из профиля WesiOS, закрепляется как владелец. Маркер лежит
/// на сервере и остаётся привязан к record id даже после смены email/логина.
function portalClaimOwner(e) {
  if (e.hasSuperuserAuth()) return;
  if (!e.auth) throw new UnauthorizedError("Требуется вход владельца WesiOS");
  if (portalOwnerMarker(e.app, e.auth.id)) return;

  if (portalAnyOwnerMarker(e.app)) {
    throw new ForbiddenError("Профиль владельца уже закреплён за другой учётной записью");
  }

  const email = e.auth.getString("email").trim().toLowerCase();
  if (email.endsWith("@wesi.local") || !e.auth.getBool("verified")) {
    throw new ForbiddenError("Первичную настройку может выполнить только подтверждённая основная учётная запись");
  }

  const collection = e.app.findCollectionByNameOrId("wesios_records");
  const marker = new Record(collection);
  marker.set("owner", e.auth.id);
  marker.set("org", "wesi-inc");
  marker.set("coll", OWNER_MARKER_COLL);
  marker.set("rid", OWNER_MARKER_RID);
  marker.set("payload", {"kind": "portal-owner", "ownerId": e.auth.id});
  marker.set("stamp", new Date().toISOString());
  marker.set("deleted", false);
  e.app.save(marker);
}

function portalOwnerOnly(e) {
  if (e.hasSuperuserAuth()) return;
  if (!e.auth || !portalOwnerMarker(e.app, e.auth.id)) {
    throw new ForbiddenError("Создавать учётные записи сотрудников может только владелец");
  }
}

routerAdd("GET", "/api/wesi/portal/session", (e) => {
  const auth = e.auth;
  return e.json(200, {
    "id": auth.id,
    "email": auth.getString("email"),
    "name": auth.getString("name"),
    "username": auth.getString("username"),
  });
}, $apis.requireAuth("users"));

/// Владелец указывает собственный короткий логин и новый пароль в профиле
/// WesiOS. Меняется текущая auth-запись, а не создаётся локальная заглушка.
/// После этого те же данные принимают сайт и будущее стартовое окно WesiOS.
routerAdd("POST", "/api/wesi/portal/profile/credentials", (e) => {
  portalClaimOwner(e);
  const body = e.requestInfo().body || {};
  const login = portalLogin(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = portalLoginEmail(login);

  if (password.length < 8 || password.length > 128) {
    throw new BadRequestError("Пароль должен содержать от 8 до 128 символов");
  }

  try {
    const existing = e.app.findAuthRecordByEmail("users", email);
    if (existing.id !== e.auth.id) {
      throw new BadRequestError("Такой логин уже занят");
    }
  } catch (error) {
    if (error instanceof BadRequestError) throw error;
    // Записи с таким email нет — это нормальный путь смены логина.
  }

  const record = e.auth;
  record.setEmail(email);
  record.setPassword(password);
  record.setVerified(true);
  record.setIfFieldExists("name", name || login);
  record.setIfFieldExists("username", login);
  record.setIfFieldExists("employeeLogin", login);
  e.app.save(record);

  return e.json(200, {
    "id": record.id,
    "email": record.getString("email"),
    "login": login,
    "owner": true,
  });
}, $apis.requireAuth("users"));

/// Атомарно создаёт или обновляет серверную учётную запись сотрудника.
/// Пароль передаётся WesiOS по HTTPS только в момент создания/сброса и сразу
/// хешируется PocketBase. В ответе и логах пароль отсутствует.
routerAdd("POST", "/api/wesi/portal/employees/provision", (e) => {
  portalOwnerOnly(e);
  const body = e.requestInfo().body || {};
  const login = portalLogin(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = portalLoginEmail(login);

  if (password.length < 8 || password.length > 128) {
    throw new BadRequestError("Пароль должен содержать от 8 до 128 символов");
  }

  let record;
  let created = false;
  try {
    record = e.app.findAuthRecordByEmail("users", email);
    if (portalOwnerMarker(e.app, record.id)) {
      throw new BadRequestError("Логин владельца нельзя выдать сотруднику");
    }
  } catch (error) {
    if (error instanceof BadRequestError) throw error;
    const collection = e.app.findCollectionByNameOrId("users");
    record = new Record(collection);
    record.setEmail(email);
    created = true;
  }

  record.setPassword(password);
  record.setVerified(true);
  record.setIfFieldExists("name", name || login);
  record.setIfFieldExists("username", login);
  record.setIfFieldExists("employeeLogin", login);
  e.app.save(record);

  return e.json(created ? 201 : 200, {
    "id": record.id,
    "email": record.getString("email"),
    "name": record.getString("name"),
    "login": login,
    "created": created,
  });
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/portal/manifest", (e) => {
  const manifest = portalManifest();
  const result = {
    "version": manifest.version,
    "build": manifest.build,
    "publishedAt": manifest.publishedAt || null,
    "protected": true,
  };

  ["windows", "android"].forEach((platform) => {
    const source = manifest[platform];
    if (!source || typeof source !== "object") return;
    result[platform] = {
      "version": source.version || manifest.version,
      "build": source.build || manifest.build,
      "asset": source.asset,
      "sizeBytes": source.sizeBytes || null,
      "sha256": source.sha256 || null,
      "notes": source.notes || null,
      "download": `/api/wesi/portal/download/${platform}`,
    };
  });

  e.response.header().set("Cache-Control", "private, no-store");
  return e.json(200, result);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/portal/download/{platform}", (e) => {
  const platform = e.request.pathValue("platform");
  if (platform !== "windows" && platform !== "android") {
    throw new NotFoundError("Неизвестная платформа");
  }

  const manifest = portalManifest();
  const entry = manifest[platform];
  if (!entry || typeof entry !== "object") {
    throw new NotFoundError("Сборка для платформы не опубликована");
  }

  const path = portalSafePath(entry.path);
  const fallback = platform === "windows"
    ? "wesios-windows-x64.zip"
    : "wesios-android.apk";
  const name = portalFileName(entry.asset, fallback);

  e.response.header().set("Cache-Control", "private, no-store");
  e.response.header().set("Content-Disposition", `attachment; filename="${name}"`);
  e.response.header().set("X-WesiOS-Version", String(entry.version || manifest.version || ""));
  e.response.header().set("X-WesiOS-Build", String(entry.build || manifest.build || ""));
  return e.fileFS($os.dirFS(PORTAL_ARTIFACTS_ROOT), path);
}, $apis.requireAuth("users"));
