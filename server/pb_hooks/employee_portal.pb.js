/// Защищённые маршруты портала сотрудников WesiOS.
///
/// PocketBase сериализует каждый handler в отдельный JS-контекст. Поэтому
/// общие функции нельзя объявлять в этом *.pb.js снаружи routerAdd: внутри
/// callback они становятся undefined. Все повторно используемые функции
/// загружаются CommonJS require() непосредственно внутри каждого handler.

routerAdd("GET", "/api/wesi/portal/session", (e) => {
  const auth = e.auth;
  return e.json(200, {
    "id": auth.id,
    "email": auth.getString("email"),
    "name": auth.getString("name"),
  });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/portal/profile/credentials", (e) => {
  const portal = require(`${__hooks}/employee_portal_utils.js`);
  portal.claimOwner(e);

  const body = e.requestInfo().body || {};
  const login = portal.login(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = portal.loginEmail(login);

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
  const portal = require(`${__hooks}/employee_portal_utils.js`);

  // Старые сборки падали до создания portal-owner marker. Если marker ещё не
  // существует, первая подтверждённая основная учётная запись владельца
  // закрепляется здесь. Если marker уже есть — доступ получает только он.
  portal.claimOwner(e);
  portal.requireOwner(e);

  const body = e.requestInfo().body || {};
  const login = portal.login(body.login);
  const password = String(body.password || "");
  const name = String(body.name || "").trim();
  const email = portal.loginEmail(login);

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

  if (record && portal.ownerMarker(e.app, record.id)) {
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
  const portal = require(`${__hooks}/employee_portal_utils.js`);
  const manifest = portal.manifest();
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
  const portal = require(`${__hooks}/employee_portal_utils.js`);
  const platform = e.request.pathValue("platform");
  if (platform !== "windows" && platform !== "android") {
    throw new NotFoundError("Неизвестная платформа");
  }

  const release = portal.release();
  const manifest = release.manifest;
  const entry = manifest[platform];
  if (!entry || typeof entry !== "object") {
    throw new NotFoundError("Сборка для платформы не опубликована");
  }

  const path = portal.safePath(entry.path);
  const fallback = platform === "windows"
    ? "wesios-windows-x64.zip"
    : "wesios-android.apk";
  const name = portal.fileName(entry.asset, fallback);

  e.response.header().set("Cache-Control", "private, no-store");
  e.response.header().set("Content-Disposition", `attachment; filename="${name}"`);
  e.response.header().set("Content-Type", platform === "windows"
    ? "application/zip"
    : "application/vnd.android.package-archive");
  e.response.header().set("X-Content-Type-Options", "nosniff");
  e.response.header().set("X-WesiOS-Version", String(entry.version || manifest.version || ""));
  e.response.header().set("X-WesiOS-Build", String(entry.build || manifest.build || ""));
  return e.fileFS($os.dirFS(release.root), path);
}, $apis.requireAuth("users"));
