/// Shared helpers for employee_portal.pb.js.
///
/// PocketBase executes every route handler in an isolated JS context, so
/// functions declared at the top level of a *.pb.js file are NOT visible from
/// the serialized handler. CommonJS modules loaded with require() are the
/// supported way to share code between handlers.

const OWNER_MARKER_COLL = "system";
const OWNER_MARKER_RID = "portal-owner";

function readText(fs, name) {
  const raw = fs.readFile(name);
  if (typeof raw === "string") return raw;
  return String.fromCharCode.apply(null, raw);
}

function release() {
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
      const manifest = JSON.parse(readText(fs, "app/app-manifest.json"));
      if (!manifest || typeof manifest !== "object") continue;
      return {"root": root, "manifest": manifest};
    } catch (error) {
      lastError = error;
    }
  }
  console.log("employee portal manifest error:", lastError);
  throw new NotFoundError("Актуальная сборка WesiOS ещё не опубликована");
}

function manifest() {
  return release().manifest;
}

function safePath(value) {
  if (typeof value !== "string" || value === "") {
    throw new NotFoundError("Файл сборки не указан");
  }
  const clean = $filepath.clean(value).replace(/\\/g, "/");
  if (!clean.startsWith("app/") || clean.indexOf("../") >= 0 || clean.startsWith("/")) {
    throw new ForbiddenError("Недопустимый путь сборки");
  }
  return clean;
}

function fileName(value, fallback) {
  if (typeof value !== "string" || value === "") return fallback;
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function login(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
    throw new BadRequestError(
      "Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание",
    );
  }
  return normalized;
}

function loginEmail(value) {
  return login(value) + "@wesi.local";
}

function ownerMarker(app, ownerId) {
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

function anyOwnerMarker(app) {
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

/// Establishes the first verified primary account as owner, or validates the
/// already claimed owner. This makes employee provisioning self-healing when
/// older builds failed before /profile/credentials could create the marker.
function claimOwner(e) {
  if (e.hasSuperuserAuth()) return;
  if (!e.auth) throw new UnauthorizedError("Требуется вход владельца WesiOS");
  if (ownerMarker(e.app, e.auth.id)) return;

  if (anyOwnerMarker(e.app)) {
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

function requireOwner(e) {
  if (e.hasSuperuserAuth()) return;
  if (!e.auth || !ownerMarker(e.app, e.auth.id)) {
    throw new ForbiddenError("Создавать учётные записи сотрудников может только владелец");
  }
}

module.exports = {
  release,
  manifest,
  safePath,
  fileName,
  login,
  loginEmail,
  ownerMarker,
  anyOwnerMarker,
  claimOwner,
  requireOwner,
};
