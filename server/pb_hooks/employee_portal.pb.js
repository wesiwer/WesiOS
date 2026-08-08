/// Защищённые маршруты портала сотрудников WesiOS.
///
/// В PocketBase каждый handler сериализуется и выполняется в изолированном
/// контексте. Поэтому все функции, которые использует route, определяются
/// внутри самого callback. Иначе production получает ReferenceError ещё до
/// выполнения бизнес-логики.

routerAdd("GET", "/api/wesi/portal/session", (e) => {
  const auth = e.auth;
  return e.json(200, {
    "id": auth.id,
    "email": auth.getString("email"),
    "name": auth.getString("name"),
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/portal/profile/credentials", (e) => {
  const normalizeLogin = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
      throw new BadRequestError(
        "Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание",
      );
    }
    return normalized;
  };
  const ownerMarker = (ownerId) => {
    try {
      return e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='" + ownerId + "' && coll='system' && rid='portal-owner' && deleted=false",
      );
    } catch (_) {
      return null;
    }
  };
  const anyOwnerMarker = () => {
    try {
      return e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid='portal-owner' && deleted=false",
      );
    } catch (_) {
      return null;
    }
  };
  const claimOwner = () => {
    if (e.hasSuperuserAuth()) return;
    if (!e.auth) throw new UnauthorizedError("Требуется вход владельца WesiOS");
    if (ownerMarker(e.auth.id)) return;
    if (anyOwnerMarker()) {
      throw new ForbiddenError("Профиль владельца уже закреплён за другой учётной записью");
    }
    const currentEmail = e.auth.getString("email").trim().toLowerCase();
    if (currentEmail.endsWith("@wesi.local") || !e.auth.getBool("verified")) {
      throw new ForbiddenError(
        "Первичную настройку может выполнить только подтверждённая основная учётная запись",
      );
    }
    const collection = e.app.findCollectionByNameOrId("wesios_records");
    const marker = new Record(collection);
    marker.set("owner", e.auth.id);
    marker.set("org", "wesi-inc");
    marker.set("coll", "system");
    marker.set("rid", "portal-owner");
    marker.set("payload", {"kind": "portal-owner", "ownerId": e.auth.id});
    marker.set("stamp", new Date().toISOString());
    marker.set("deleted", false);
    e.app.save(marker);
  };

  claimOwner();
  const body = e.requestInfo().body || {};
  const login = normalizeLogin(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = login + "@wesi.local";

  if (password.length < 8 || password.length > 128) {
    throw new BadRequestError("Пароль должен содержать от 8 до 128 символов");
  }

  let existing = null;
  try {
    existing = e.app.findAuthRecordByEmail("users", email);
  } catch (_) {
    existing = null;
  }
  if (existing && existing.id !== e.auth.id) {
    throw new BadRequestError("Такой логин уже занят");
  }

  const record = e.auth;
  record.setEmail(email);
  record.setPassword(password);
  record.setVerified(true);
  record.setIfFieldExists("name", name || login);
  e.app.save(record);

  return e.json(200, {
    "id": record.id,
    "email": record.getString("email"),
    "login": login,
    "owner": true,
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/portal/employees/provision", (e) => {
  const normalizeLogin = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
      throw new BadRequestError(
        "Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание",
      );
    }
    return normalized;
  };
  const ownerMarker = (ownerId) => {
    try {
      return e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='" + ownerId + "' && coll='system' && rid='portal-owner' && deleted=false",
      );
    } catch (_) {
      return null;
    }
  };
  const anyOwnerMarker = () => {
    try {
      return e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid='portal-owner' && deleted=false",
      );
    } catch (_) {
      return null;
    }
  };
  const claimOwner = () => {
    if (e.hasSuperuserAuth()) return;
    if (!e.auth) throw new UnauthorizedError("Требуется вход владельца WesiOS");
    if (ownerMarker(e.auth.id)) return;
    if (anyOwnerMarker()) {
      throw new ForbiddenError("Профиль владельца уже закреплён за другой учётной записью");
    }
    const currentEmail = e.auth.getString("email").trim().toLowerCase();
    if (currentEmail.endsWith("@wesi.local") || !e.auth.getBool("verified")) {
      throw new ForbiddenError(
        "Первичную настройку может выполнить только подтверждённая основная учётная запись",
      );
    }
    const collection = e.app.findCollectionByNameOrId("wesios_records");
    const marker = new Record(collection);
    marker.set("owner", e.auth.id);
    marker.set("org", "wesi-inc");
    marker.set("coll", "system");
    marker.set("rid", "portal-owner");
    marker.set("payload", {"kind": "portal-owner", "ownerId": e.auth.id});
    marker.set("stamp", new Date().toISOString());
    marker.set("deleted", false);
    e.app.save(marker);
  };

  // На production marker отсутствует, потому что прежний handler падал раньше
  // его создания. Первая подтверждённая основная учётка закрепляет владельца
  // прямо здесь; после этого provisioning доступен только ей.
  claimOwner();
  if (!e.hasSuperuserAuth() && (!e.auth || !ownerMarker(e.auth.id))) {
    throw new ForbiddenError("Создавать учётные записи сотрудников может только владелец");
  }

  const body = e.requestInfo().body || {};
  const login = normalizeLogin(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = login + "@wesi.local";

  if (password.length < 8 || password.length > 128) {
    throw new BadRequestError("Пароль должен содержать от 8 до 128 символов");
  }

  let record = null;
  let created = false;
  try {
    record = e.app.findAuthRecordByEmail("users", email);
  } catch (_) {
    record = null;
  }

  if (record && ownerMarker(record.id)) {
    throw new BadRequestError("Логин владельца нельзя выдать сотруднику");
  }

  if (!record) {
    const collection = e.app.findCollectionByNameOrId("users");
    record = new Record(collection);
    record.setEmail(email);
    created = true;
  }

  record.setPassword(password);
  record.setVerified(true);
  record.setIfFieldExists("name", name || login);
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
  const readText = (fs, name) => {
    const raw = fs.readFile(name);
    if (typeof raw === "string") return raw;
    return String.fromCharCode.apply(null, raw);
  };
  const release = () => {
    const configured = $os.getenv("WESI_ARTIFACTS_DIR");
    const roots = [
      configured,
      "/srv/wesi-artifacts",
      "/opt/pocketbase/pb_public/artifacts",
    ].filter((value, index, all) => value && all.indexOf(value) === index);
    let lastError = null;
    for (const root of roots) {
      try {
        const fs = $os.dirFS(root);
        const value = JSON.parse(readText(fs, "app/app-manifest.json"));
        if (value && typeof value === "object") {
          return {"root": root, "manifest": value};
        }
      } catch (error) {
        lastError = error;
      }
    }
    console.log("employee portal manifest error:", lastError);
    throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
  };

  const manifest = release().manifest;
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
  const readText = (fs, name) => {
    const raw = fs.readFile(name);
    if (typeof raw === "string") return raw;
    return String.fromCharCode.apply(null, raw);
  };
  const release = () => {
    const configured = $os.getenv("WESI_ARTIFACTS_DIR");
    const roots = [
      configured,
      "/srv/wesi-artifacts",
      "/opt/pocketbase/pb_public/artifacts",
    ].filter((value, index, all) => value && all.indexOf(value) === index);
    let lastError = null;
    for (const root of roots) {
      try {
        const fs = $os.dirFS(root);
        const value = JSON.parse(readText(fs, "app/app-manifest.json"));
        if (value && typeof value === "object") {
          return {"root": root, "manifest": value};
        }
      } catch (error) {
        lastError = error;
      }
    }
    console.log("employee portal manifest error:", lastError);
    throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
  };
  const safePath = (value) => {
    if (typeof value !== "string" || value === "") {
      throw new NotFoundError("Файл сборки не указан");
    }
    const clean = $filepath.clean(value).replace(/\\/g, "/");
    if (!clean.startsWith("app/") || clean.indexOf("../") >= 0 || clean.startsWith("/")) {
      throw new ForbiddenError("Недопустимый путь сборки");
    }
    return clean;
  };
  const fileName = (value, fallback) => {
    if (typeof value !== "string" || value === "") return fallback;
    return value.replace(/[^a-zA-Z0-9._-]/g, "_");
  };

  const platform = e.request.pathValue("platform");
  if (platform !== "windows" && platform !== "android") {
    throw new NotFoundError("Неизвестная платформа");
  }

  const current = release();
  const manifest = current.manifest;
  const entry = manifest[platform];
  if (!entry || typeof entry !== "object") {
    throw new NotFoundError("Сборка для платформы не опубликована");
  }

  const path = safePath(entry.path);
  const fallback = platform === "windows"
    ? "wesios-windows-x64.zip"
    : "wesios-android.apk";
  const name = fileName(entry.asset, fallback);

  e.response.header().set("Cache-Control", "private, no-store");
  e.response.header().set("Content-Disposition", `attachment; filename="${name}"`);
  e.response.header().set("Content-Type", platform === "windows"
    ? "application/zip"
    : "application/vnd.android.package-archive");
  e.response.header().set("X-Content-Type-Options", "nosniff");
  e.response.header().set("X-WesiOS-Version", String(entry.version || manifest.version || ""));
  e.response.header().set("X-WesiOS-Build", String(entry.build || manifest.build || ""));
  return e.fileFS($os.dirFS(current.root), path);
}, $apis.requireAuth("users"));
