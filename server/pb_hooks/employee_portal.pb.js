/// Защищённые маршруты портала сотрудников WesiOS.
///
/// Файл устанавливается в /opt/pocketbase/pb_hooks. Статическая страница
/// входа открыта всем, но manifest и установочные файлы эти маршруты отдают
/// только после действующей авторизации в коллекции users.

const PORTAL_ARTIFACTS_ROOT = $os.getenv("WESI_ARTIFACTS_DIR") ||
  "/opt/pocketbase/pb_public/artifacts";
const PORTAL_OWNER_EMAIL = ($os.getenv("WESI_OWNER_EMAIL") ||
  "wesi@wesios.local").toLowerCase();

function portalReadText(fs, name) {
  const raw = fs.readFile(name);
  if (typeof raw === "string") {
    return raw;
  }
  // readFile может вернуть массив байтов. Manifest маленький, поэтому
  // преобразование целиком безопасно и проще потокового чтения.
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

function portalOwnerOnly(e) {
  if (e.hasSuperuserAuth()) return;
  if (!e.auth || e.auth.getString("email").toLowerCase() !== PORTAL_OWNER_EMAIL) {
    throw new ForbiddenError("Только владелец может создавать учётные записи сотрудников");
  }
}

function portalLoginEmail(login, email) {
  if (typeof email === "string" && email.trim() !== "") {
    return email.trim().toLowerCase();
  }
  const normalized = String(login || "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
    throw new BadRequestError("Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание");
  }
  return normalized + "@wesi.local";
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

/// Создание/обновление учётной записи портала из модуля сотрудников WesiOS.
///
/// Пароль приходит только в момент создания/сброса, по HTTPS, и сразу
/// превращается PocketBase в хеш. В логах и ответе пароль не возвращается.
routerAdd("POST", "/api/wesi/portal/employees/provision", (e) => {
  portalOwnerOnly(e);
  const body = e.requestInfo().body || {};
  const login = String(body.login || "").trim().toLowerCase();
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = portalLoginEmail(login, body.email);

  if (password.length < 8 || password.length > 128) {
    throw new BadRequestError("Пароль должен содержать от 8 до 128 символов");
  }

  let record;
  let created = false;
  try {
    record = e.app.findAuthRecordByEmail("users", email);
  } catch (_) {
    const collection = e.app.findCollectionByNameOrId("users");
    record = new Record(collection);
    record.setEmail(email);
    created = true;
  }

  record.setPassword(password);
  record.setVerified(true);
  record.setIfFieldExists("name", name || login);
  record.setIfFieldExists("username", login);
  e.app.save(record);

  return e.json(created ? 201 : 200, {
    "id": record.id,
    "email": record.getString("email"),
    "name": record.getString("name"),
    "created": created,
  });
}, $apis.requireAuth());

routerAdd("GET", "/api/wesi/portal/manifest", (e) => {
  const manifest = portalManifest();

  // Путь на диске нужен только серверу. Клиент получает стабильные
  // защищённые endpoints и метаданные релиза.
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
