// Reliable change token for WesiOS synchronization.
//
// The previous revision endpoint returned only the id+updated value of the
// newest wesios_records row. Two distinct writes can share the same database
// timestamp; if the second row sorts below the first one, that token does not
// change and a live client never starts a pull.
//
// Every persisted business record now touches an owner-scoped marker with a
// fresh random nonce. Revision reads the marker payload, not its timestamp.
// Therefore every committed write changes the observable token even when
// PocketBase timestamps collide.

const dataAccess = require(
  (typeof __hooks !== "undefined" ? __hooks + "/" : "./") +
    "wesi_sync_data_access.js",
);

const markerCollection = "__sync_revision__";
const markerRid = "global";

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? parsed
        : {};
    }
  } catch (_) {}
  return {};
}

function markerRows(app, owner) {
  if (!owner) return [];
  return dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid}",
    "id",
    0,
    0,
    { owner: owner, coll: markerCollection, rid: markerRid },
  );
}

function nonce() {
  // Randomness, not wall-clock ordering, is the invariant. Date.now() remains
  // useful in diagnostics but two writes in the same millisecond must still
  // produce different revisions.
  return String(Date.now()) + ":" + $security.randomString(24);
}

function touch(app, owner) {
  owner = String(owner || "").trim();
  if (!owner) return;

  const value = nonce();
  const existing = markerRows(app, owner);
  if (!existing.length) {
    const collection = app.findCollectionByNameOrId("wesios_records");
    const record = new Record(collection);
    record.set("owner", owner);
    record.set("org", "__sync_revision__");
    record.set("coll", markerCollection);
    record.set("rid", markerRid);
    record.set("payload", { nonce: value });
    record.set("stamp", new Date().toISOString());
    record.set("deleted", false);
    app.save(record);
    return;
  }

  // If an old concurrent first-write ever produced duplicate marker rows,
  // update all of them to the same nonce. readOwner() combines every marker,
  // so duplicates remain harmless and no migration is required.
  for (const record of existing) {
    record.set("payload", { nonce: value });
    record.set("stamp", new Date().toISOString());
    record.set("deleted", false);
    app.save(record);
  }
}

function legacyOwnerRevision(app, owner) {
  if (!owner) return "empty";
  const rows = dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll!={:marker}",
    "-updated,-id",
    1,
    0,
    { owner: owner, marker: markerCollection },
  );
  if (!rows.length) return "empty";
  const first = rows[0];
  return "legacy:" + String(first.id || "") + "|" + first.getString("updated");
}

function readOwner(app, owner) {
  owner = String(owner || "").trim();
  if (!owner) return "empty";
  const rows = markerRows(app, owner);
  if (!rows.length) return legacyOwnerRevision(app, owner);

  // Normally there is one row. Sorting nonce values also makes a historical
  // duplicate set deterministic; touching the owner rewrites all duplicates
  // to a fresh value and therefore changes this token.
  const values = [];
  for (const row of rows) {
    const value = String(payloadOf(row).nonce || "").trim();
    if (value) values.push(value);
  }
  if (!values.length) return legacyOwnerRevision(app, owner);
  values.sort();
  return "marker:" + values.join(",");
}

function readForContext(app, companyOwner, privateOwner) {
  const company = String(companyOwner || "").trim();
  const personal = String(privateOwner || "").trim();
  const companyRevision = readOwner(app, company);
  const privateRevision = personal && personal !== company
    ? readOwner(app, personal)
    : companyRevision;
  return "company=" + companyRevision + "|private=" + privateRevision;
}

function isMarker(record) {
  if (!record) return false;
  return record.getString("coll") === markerCollection;
}

module.exports = {
  markerCollection,
  markerRid,
  touch,
  readOwner,
  readForContext,
  isMarker,
};
