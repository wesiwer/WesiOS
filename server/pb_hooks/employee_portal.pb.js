/// Защищённые маршруты портала сотрудников WesiOS.
///
/// Файл устанавливается в /opt/pocketbase/pb_hooks. Статическая страница
/// входа открыта всем, но manifest и установочные файлы эти маршруты отдают
/// только после действующей авторизации в коллекции users.

const PORTAL_ARTIFACTS_ROOT = $os.getenv("WESI_ARTIFACTS_DIR") ||
  "/opt/pocketbase/pb_public/artifacts";

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
  const clean = $filepath.clean(value).replaceAll("\\", "/");
  if (!clean.startsWith("app/") || clean.includes("../") || clean.startsWith("/")) {
    throw new ForbiddenError("Недопустимый путь сборки");
  }
  return clean;
}

function portalFileName(value, fallback) {
  if (typeof value !== "string" || value === "") return fallback;
  return value.replaceAll(/[^a-zA-Z0-9._-]/g, "_");
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
