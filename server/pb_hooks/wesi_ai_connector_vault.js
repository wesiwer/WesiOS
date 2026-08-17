const COLLECTION = "wesi_ai_connector_vault";
const MAX_SECRET_JSON = 128 * 1024;

class ConnectorVaultError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function key() {
  let value = "";
  try { value = String($os.getenv("WESI_CONNECTOR_VAULT_KEY") || ""); } catch (_) {}
  if (value.length !== 32) {
    throw new ConnectorVaultError("CONNECTOR_VAULT_NOT_CONFIGURED", "Connector credential vault is not configured");
  }
  return value;
}

function coll(e) {
  try { return e.app.findCollectionByNameOrId(COLLECTION); }
  catch (_) { throw new ConnectorVaultError("CONNECTOR_VAULT_NOT_MIGRATED", "Connector credential vault collection is unavailable"); }
}

function owner(ctx) {
  const value = String((ctx && ctx.ownerId) || "").trim();
  if (!value || value.length > 80) throw new ConnectorVaultError("CONNECTOR_OWNER_INVALID", "Connector owner is invalid");
  return value;
}

function encryptValue(value) {
  let raw;
  try { raw = JSON.stringify(value); } catch (_) { throw new ConnectorVaultError("CONNECTOR_SECRET_INVALID", "Connector secret payload is invalid"); }
  if (!raw || raw.length > MAX_SECRET_JSON) throw new ConnectorVaultError("CONNECTOR_SECRET_TOO_LARGE", "Connector secret payload is too large");
  return String($security.encrypt(raw, key()));
}

function decryptValue(ciphertext) {
  let raw;
  try { raw = String($security.decrypt(String(ciphertext || ""), key())); }
  catch (_) { throw new ConnectorVaultError("CONNECTOR_CREDENTIAL_CORRUPT", "Connector credential cannot be decrypted"); }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("bad");
    return parsed;
  } catch (_) { throw new ConnectorVaultError("CONNECTOR_CREDENTIAL_CORRUPT", "Connector credential payload is corrupt"); }
}

function readRows(e, filter, sort, limit, params) {
  try {
    return e.app.findRecordsByFilter(
      COLLECTION,
      filter,
      sort,
      Math.max(1, Math.min(Number(limit || 100), 1000)),
      0,
      params,
    );
  } catch (_) {
    throw new ConnectorVaultError("CONNECTOR_VAULT_READ_FAILED", "Connector credential vault could not be read");
  }
}

function findRecord(e, ctx, rid) {
  const rows = readRows(
    e,
    "owner={:owner} && rid={:rid}",
    "id",
    1,
    {owner: owner(ctx), rid: String(rid || "")},
  );
  return rows.length ? rows[0] : null;
}

function save(e, ctx, rid, provider, kind, value, expiresAt) {
  const id = String(rid || "").trim();
  if (!/^[A-Za-z0-9._:-]{1,180}$/.test(id)) throw new ConnectorVaultError("CONNECTOR_ID_INVALID", "Connector record id is invalid");
  const now = new Date().toISOString();
  let record = findRecord(e, ctx, id);
  if (!record) record = new Record(coll(e));
  record.set("owner", owner(ctx));
  record.set("rid", id);
  record.set("provider", String(provider || "").slice(0, 40));
  record.set("kind", String(kind || "").slice(0, 40));
  record.set("ciphertext", encryptValue(value));
  record.set("expiresAt", expiresAt ? String(expiresAt).slice(0, 64) : "");
  record.set("stamp", now);
  e.app.save(record);
}

function load(e, ctx, rid, expectedKind) {
  const record = findRecord(e, ctx, rid);
  if (!record || (expectedKind && String(record.get("kind")) !== expectedKind)) return null;
  const expiresAt = String(record.get("expiresAt") || "");
  if (expiresAt && Date.parse(expiresAt) <= Date.now()) {
    try { e.app.delete(record); } catch (_) {}
    return null;
  }
  return decryptValue(record.get("ciphertext"));
}

function remove(e, ctx, rid) {
  const record = findRecord(e, ctx, rid);
  if (record) e.app.delete(record);
}

function safeCredential(value) {
  if (!value || typeof value !== "object") return null;
  return {
    credentialId: String(value.credentialId || ""),
    provider: String(value.provider || ""),
    accountLogin: String(value.accountLogin || ""),
    accountId: String(value.accountId || ""),
    scopes: Array.isArray(value.scopes) ? value.scopes.map(String).slice(0, 32) : [],
    status: String(value.status || "invalid"),
    createdAt: String(value.createdAt || ""),
    updatedAt: String(value.updatedAt || ""),
  };
}

function listCredentials(e, ctx, provider) {
  const records = readRows(
    e,
    "owner={:owner} && kind='credential' && provider={:provider}",
    "-stamp",
    100,
    {owner: owner(ctx), provider: String(provider || "")},
  );
  const out = [];
  for (const record of records) {
    try {
      const value = decryptValue(record.get("ciphertext"));
      const safe = safeCredential(value);
      if (safe) out.push(safe);
    } catch (_) {}
  }
  return out;
}

function requireCredential(e, ctx, provider, credentialId) {
  let id = String(credentialId || "").trim();
  if (!id) {
    const active = listCredentials(e, ctx, provider).filter((item) => item.status === "active");
    if (active.length !== 1) throw new ConnectorVaultError("CONNECTOR_CREDENTIAL_REQUIRED", "Select a connector credential");
    id = active[0].credentialId;
  }
  const value = load(e, ctx, id, "credential");
  if (!value || value.provider !== provider || value.status !== "active" || !String(value.accessToken || "")) {
    throw new ConnectorVaultError("CONNECTOR_CREDENTIAL_UNAVAILABLE", "Connector credential is missing, expired or revoked");
  }
  return value;
}

function markCredentialStatus(e, ctx, credentialId, status) {
  const value = load(e, ctx, credentialId, "credential");
  if (!value) return;
  value.status = String(status || "invalid");
  value.updatedAt = new Date().toISOString();
  save(e, ctx, credentialId, value.provider, "credential", value, "");
}

module.exports = {
  ConnectorVaultError,
  ready: () => { try { key(); return true; } catch (_) { return false; } },
  saveFlow: (e, ctx, id, provider, value, expiresAt) => save(e, ctx, id, provider, "flow", value, expiresAt),
  loadFlow: (e, ctx, id) => load(e, ctx, id, "flow"),
  removeFlow: (e, ctx, id) => remove(e, ctx, id),
  saveCredential: (e, ctx, id, provider, value) => save(e, ctx, id, provider, "credential", value, ""),
  listCredentials,
  requireCredential,
  removeCredential: (e, ctx, id) => remove(e, ctx, id),
  markCredentialStatus,
  safeCredential,
  _test: {encryptValue, decryptValue},
};
