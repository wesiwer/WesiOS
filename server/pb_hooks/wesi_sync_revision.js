// Reliable change token for WesiOS synchronization.
//
// The old endpoint returned only the id+updated value of the newest business
// row. Two different writes can share the same database timestamp; when the
// second row sorts below the first, that token remains unchanged and live
// clients never pull it.
//
// Every persisted wesios_records business row now touches an owner-scoped
// marker with a fresh random nonce. The returned token ALSO carries the newest
// non-marker row as a fallback. The nonce closes timestamp collisions; the
// fallback still changes for normal writes if marker maintenance ever suffers
// a transient failure after the business record has already committed.

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

  // Historical concurrent first-writes could theoretically create duplicate
  // markers because (owner,coll,rid) is not a database unique constraint.
  // Keep duplicates harmless by rewriting every marker to the same nonce.
  for (const record of existing) {
    record.set("payload", { nonce: value });
    record.set("stamp", new Date().toISOString());
    record.set("deleted", false);
    app.save(record);
  }
}

function latestBusinessRevision(app, owner) {
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
  return String(first.id || "") + "|" + first.getString("updated");
}

function readOwner(app, owner) {
  owner = String(owner || "").trim();
  if (!owner) return "empty";

  const latest = latestBusinessRevision(app, owner);
  const rows = markerRows(app, owner);
  if (!rows.length) return "legacy:" + latest;

  const values = [];
  for (const row of rows) {
    const value = String(payloadOf(row).nonce || "").trim();
    if (value) values.push(value);
  }
  if (!values.length) return "legacy:" + latest;
  values.sort();

  // `latest` is intentionally included even when a marker exists. If a
  // business save committed but touch() failed, ordinary distinct-timestamp
  // writes still invalidate polling. Equal-timestamp writes remain protected
  // by the nonce path during normal marker operation.
  return "marker:" + values.join(",") + "|latest:" + latest;
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
