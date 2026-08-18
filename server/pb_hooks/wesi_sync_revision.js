// Reliable change token for WesiOS synchronization.
//
// Every persisted wesios_records business row touches an owner-scoped marker.
// New clients read its random nonce. Older clients still call the legacy
// revision endpoint, which sorts by record `stamp`; therefore the marker stamp
// is maintained as a strictly increasing logical clock that is ALWAYS newer
// than every business stamp for the same owner.

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

function latestBusinessByStamp(app, owner) {
  if (!owner) return null;
  const rows = dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll!={:marker}",
    "-stamp,-id",
    1,
    0,
    { owner: owner, marker: markerCollection },
  );
  return rows.length ? rows[0] : null;
}

function nonce() {
  return String(Date.now()) + ":" + $security.randomString(24);
}

function nextMarkerStamp(existing, businessStamp) {
  let previousMs = -1;
  for (const record of existing || []) {
    const parsed = Date.parse(String(record.getString("stamp") || ""));
    if (Number.isFinite(parsed) && parsed > previousMs) previousMs = parsed;
  }

  const businessMs = Date.parse(String(businessStamp || ""));
  const nextMs = Math.max(
    Date.now(),
    previousMs + 1,
    Number.isFinite(businessMs) ? businessMs + 1 : -1,
  );
  return new Date(nextMs).toISOString();
}

function updateMarkers(app, owner, existing, businessStamp) {
  if (!existing || !existing.length) return false;
  const value = nonce();
  const markerStamp = nextMarkerStamp(existing, businessStamp);

  // Old installations could historically have duplicate marker rows. The
  // schema migration collapses them, but updating every row here keeps this
  // runtime backwards-compatible until that migration is applied.
  for (const record of existing) {
    record.set("payload", { nonce: value });
    record.set("stamp", markerStamp);
    record.set("deleted", false);
    app.save(record);
  }
  return true;
}

function touch(app, owner) {
  owner = String(owner || "").trim();
  if (!owner) return;

  let existing = markerRows(app, owner);
  let latestBusiness = latestBusinessByStamp(app, owner);
  let businessStamp = latestBusiness ? latestBusiness.getString("stamp") : null;

  if (updateMarkers(app, owner, existing, businessStamp)) return;

  const collection = app.findCollectionByNameOrId("wesios_records");
  const record = new Record(collection);
  record.set("owner", owner);
  record.set("org", "__sync_revision__");
  record.set("coll", markerCollection);
  record.set("rid", markerRid);
  record.set("payload", { nonce: nonce() });
  record.set("stamp", nextMarkerStamp([], businessStamp));
  record.set("deleted", false);

  try {
    app.save(record);
    return;
  } catch (createError) {
    // With UNIQUE(owner,coll,rid), two AfterSuccess hooks can both observe an
    // absent marker before either has committed its first create. The loser
    // must not silently lose its revision touch. Re-read the marker created by
    // the winner and turn this touch into a normal update.
    existing = markerRows(app, owner);
    if (!existing.length) throw createError;

    // A newer business row may have committed while the create raced, so use a
    // fresh business watermark as well as the newly-created marker stamp.
    latestBusiness = latestBusinessByStamp(app, owner);
    businessStamp = latestBusiness ? latestBusiness.getString("stamp") : null;
    if (!updateMarkers(app, owner, existing, businessStamp)) throw createError;
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

  // `latest` remains an independent fallback if marker maintenance ever fails
  // after a business row has already committed.
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
  nextMarkerStamp,
  latestBusinessByStamp,
};
