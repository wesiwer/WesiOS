const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");

const SYSTEM_OWNER = "__wesios_telegram__";
const SYSTEM_ORG = "wesi-inc";
const COLL_CODES = "telegram_link_codes";
const COLL_LINKS = "telegram_links";
const COLL_INDEX = "telegram_indexes";
const CODE_TTL_MS = 10 * 60 * 1000;

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function find(app, coll, rid) {
  return dataAccess.first(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
    {owner: SYSTEM_OWNER, coll: coll, rid: rid},
  );
}

function rows(app, coll, limit) {
  return dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && deleted=false",
    "stamp",
    Math.max(1, Math.min(Number(limit || 5000), 5000)),
    0,
    {owner: SYSTEM_OWNER, coll: coll},
  );
}

function upsert(app, coll, rid, payload) {
  let record = find(app, coll, rid);
  if (!record) {
    const collection = app.findCollectionByNameOrId("wesios_records");
    record = new Record(collection);
    record.set("owner", SYSTEM_OWNER);
    record.set("org", SYSTEM_ORG);
    record.set("coll", coll);
    record.set("rid", rid);
  }
  record.set("payload", payload);
  record.set("stamp", new Date().toISOString());
  record.set("deleted", false);
  app.save(record);
  return record;
}

function remove(app, coll, rid) {
  const record = find(app, coll, rid);
  if (!record) return false;
  record.set("deleted", true);
  record.set("stamp", new Date().toISOString());
  app.save(record);
  return true;
}

function codeRid(code) {
  return "code:" + $security.sha256(String(code || ""));
}

function authRid(authUserId) {
  return "auth:" + String(authUserId || "");
}

function telegramRid(telegramUserId) {
  return "tg:" + String(telegramUserId || "");
}

function randomCode() {
  return $security.randomStringWithAlphabet(
    28,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
  );
}

function readEnv(name) {
  try {
    if (typeof $os !== "undefined" && typeof $os.getenv === "function") {
      return String($os.getenv(name) || "").trim();
    }
  } catch (_) {}
  return "";
}

function config() {
  let file = {};
  try {
    const raw = $os.readFile(__hooks + "/.wesi-telegram.json");
    const value = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
    file = JSON.parse(value || "{}");
  } catch (_) {}
  const botToken = readEnv("WESI_TELEGRAM_BOT_TOKEN") || String(file.botToken || "").trim();
  const webhookSecret = readEnv("WESI_TELEGRAM_WEBHOOK_SECRET") || String(file.webhookSecret || "").trim();
  const botUsername = readEnv("WESI_TELEGRAM_BOT_USERNAME") || String(file.botUsername || "WesiOSBot").trim();
  const publicBaseUrl = readEnv("WESI_PUBLIC_BASE_URL") || String(file.publicBaseUrl || "https://api.wesi-inc.ru").trim().replace(/\/$/, "");
  return {
    botToken: botToken,
    webhookSecret: webhookSecret,
    botUsername: botUsername.replace(/^@/, ""),
    publicBaseUrl: /^https:\/\//.test(publicBaseUrl) ? publicBaseUrl : "https://api.wesi-inc.ru",
    ready: botToken.length >= 20 && webhookSecret.length >= 24,
  };
}

function createLinkCode(app, identity, activeOrganizationId, timezoneOffsetMinutes) {
  const now = Date.now();
  const code = randomCode();
  const payload = {
    authUserId: identity.authUserId,
    ownerId: identity.ownerId,
    employeeId: identity.employeeId,
    isOwner: identity.isOwner === true,
    activeOrganizationId: String(activeOrganizationId || ""),
    timezoneOffsetMinutes: Math.max(-840, Math.min(840, Number(timezoneOffsetMinutes || 0))),
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + CODE_TTL_MS).toISOString(),
  };
  upsert(app, COLL_CODES, codeRid(code), payload);
  return {code: code, payload: payload};
}

function consumeLinkCode(app, code) {
  const rid = codeRid(code);
  const record = find(app, COLL_CODES, rid);
  if (!record) return {ok: false, code: "LINK_CODE_INVALID"};
  const payload = payloadOf(record);
  const expiresAt = Date.parse(String(payload.expiresAt || ""));
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    remove(app, COLL_CODES, rid);
    return {ok: false, code: "LINK_CODE_EXPIRED"};
  }
  remove(app, COLL_CODES, rid);
  return {ok: true, payload: payload};
}

function linkByAuth(app, authUserId) {
  const record = find(app, COLL_LINKS, authRid(authUserId));
  if (!record) return null;
  const payload = payloadOf(record);
  return String(payload.revokedAt || "") ? null : {record: record, payload: payload};
}

function linkByTelegram(app, telegramUserId) {
  const index = find(app, COLL_INDEX, telegramRid(telegramUserId));
  if (!index) return null;
  const ip = payloadOf(index);
  const authUserId = String(ip.authUserId || "");
  return authUserId ? linkByAuth(app, authUserId) : null;
}

function saveLink(app, value) {
  const now = new Date().toISOString();
  const authUserId = String(value.authUserId || "");
  const telegramUserId = String(value.telegramUserId || "");
  if (!authUserId || !telegramUserId) throw new Error("telegram link identity missing");
  const previous = linkByAuth(app, authUserId);
  const payload = Object.assign({}, previous ? previous.payload : {}, value, {
    authUserId: authUserId,
    telegramUserId: telegramUserId,
    telegramChatId: String(value.telegramChatId || telegramUserId),
    linkedAt: previous && previous.payload.linkedAt ? previous.payload.linkedAt : now,
    updatedAt: now,
    revokedAt: null,
  });
  if (!payload.notificationPrefs || typeof payload.notificationPrefs !== "object") {
    payload.notificationPrefs = {
      risk: true,
      overdue: true,
      quietFromHour: 23,
      quietToHour: 8,
      timezoneOffsetMinutes: Number(value.timezoneOffsetMinutes || 0),
    };
  }
  upsert(app, COLL_LINKS, authRid(authUserId), payload);
  upsert(app, COLL_INDEX, telegramRid(telegramUserId), {authUserId: authUserId, updatedAt: now});
  return payload;
}

function revokeByAuth(app, authUserId, reason) {
  const row = find(app, COLL_LINKS, authRid(authUserId));
  if (!row) return false;
  const payload = payloadOf(row);
  payload.revokedAt = new Date().toISOString();
  payload.revokeReason = String(reason || "manual").slice(0, 120);
  row.set("payload", payload);
  row.set("stamp", new Date().toISOString());
  app.save(row);
  if (payload.telegramUserId) remove(app, COLL_INDEX, telegramRid(payload.telegramUserId));
  return true;
}

function updateLink(app, payload) {
  return saveLink(app, payload);
}

function resolveIdentityForAuth(app, authUserId) {
  const id = String(authUserId || "");
  if (!id) return null;
  const ownerMarker = dataAccess.first(
    app,
    "wesios_records",
    "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false",
    {owner: id},
  );
  if (ownerMarker) {
    return {isOwner: true, ownerId: id, employeeId: "owner", authUserId: id, modules: []};
  }
  const account = dataAccess.first(
    app,
    "wesios_records",
    "coll='system' && rid={:rid} && deleted=false",
    {rid: "portal-account:" + id},
  );
  if (!account) return null;
  const ap = payloadOf(account);
  const ownerId = String(account.getString("owner") || "");
  const employeeId = String(ap.employeeId || "");
  if (!ownerId || !employeeId) return null;
  const employee = dataAccess.first(
    app,
    "wesios_records",
    "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
    {owner: ownerId, rid: employeeId},
  );
  if (!employee) return null;
  const ep = payloadOf(employee);
  const status = String(ep.status || "active").toLowerCase();
  if (ep.active === false || ep.deactivated === true || ["inactive", "disabled", "deactivated", "archived"].indexOf(status) >= 0) return null;
  const permissions = ep.permissions && typeof ep.permissions === "object"
    ? ep.permissions
    : (ap.snapshot && ap.snapshot.permissions && typeof ap.snapshot.permissions === "object" ? ap.snapshot.permissions : {});
  return {
    isOwner: false,
    ownerId: ownerId,
    employeeId: employeeId,
    authUserId: id,
    modules: Array.isArray(permissions.modules) ? permissions.modules.map(String) : [],
  };
}

function visibleOrganizations(app, identity) {
  const orgRows = dataAccess.records(app, "wesios_records", "owner={:owner} && coll='organizations' && deleted=false", "id", 1000, 0, {owner: identity.ownerId});
  const grantRows = identity.isOwner ? [] : dataAccess.records(app, "wesios_records", "owner={:owner} && coll='organization_grants' && deleted=false", "id", 1000, 0, {owner: identity.ownerId});
  const orgs = {};
  const parents = {};
  for (const row of orgRows) {
    const p = payloadOf(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    orgs[id] = {id: id, name: String(p.name || id), parentId: p.parentId == null ? null : String(p.parentId)};
    parents[id] = orgs[id].parentId;
  }
  if (identity.isOwner) return Object.keys(orgs).map((id) => orgs[id]);
  const grants = grantRows.map(payloadOf).filter((g) => String(g.employeeId || "") === identity.employeeId);
  const allowed = {};
  for (const id of Object.keys(orgs)) {
    let cursor = id;
    let first = true;
    while (cursor) {
      const hit = grants.some((g) => {
        if (String(g.organizationId || "") !== cursor) return false;
        if (!first && g.includeSubtree !== true) return false;
        const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
        return perms.indexOf("view") >= 0;
      });
      if (hit) { allowed[id] = true; break; }
      first = false;
      cursor = parents[cursor];
    }
  }
  return Object.keys(allowed).filter((id) => allowed[id] && orgs[id]).map((id) => orgs[id]);
}

function selectVisibleOrganization(app, identity, requested) {
  const visible = visibleOrganizations(app, identity);
  if (!visible.length) return {id: "", organizations: visible};
  const query = String(requested || "").trim().toLowerCase();
  if (query) {
    const exact = visible.filter((o) => o.id.toLowerCase() === query || o.name.toLowerCase() === query);
    if (exact.length === 1) return {id: exact[0].id, organizations: visible};
    const partial = visible.filter((o) => o.name.toLowerCase().indexOf(query) >= 0);
    if (partial.length === 1) return {id: partial[0].id, organizations: visible};
  }
  const root = visible.find((o) => o.id === "org_wesi_inc");
  return {id: root ? root.id : visible[0].id, organizations: visible};
}

module.exports = {
  SYSTEM_OWNER,
  COLL_CODES,
  COLL_LINKS,
  COLL_INDEX,
  CODE_TTL_MS,
  payloadOf,
  config,
  rows,
  createLinkCode,
  consumeLinkCode,
  linkByAuth,
  linkByTelegram,
  saveLink,
  updateLink,
  revokeByAuth,
  resolveIdentityForAuth,
  visibleOrganizations,
  selectVisibleOrganization,
};
