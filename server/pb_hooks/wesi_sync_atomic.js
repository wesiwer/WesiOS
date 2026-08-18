// Atomic authoritative write boundary for WesiOS sync rows.
//
// A normal read -> LWW decide -> save sequence is not sufficient under
// concurrency: two requests can both read the same old row, both decide they
// are newer, and then the physically-last save can overwrite the true newer
// timestamp. PocketBase allows only one writer/transaction at a time, so the
// final read + decision + save must happen in runInTransaction(txApp).

const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
const dataAccess = require(base + "wesi_sync_data_access.js");
const lww = require(base + "wesi_sync_lww.js");

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

function commit(app, input) {
  const owner = String(input.owner || "").trim();
  const org = String(input.org || "");
  const coll = String(input.coll || "").trim();
  const rid = String(input.rid || "").trim();
  const stamp = String(input.stamp || "");
  const deleted = input.deleted === true;
  const suppliedPayload = input.payload && typeof input.payload === "object" &&
      !Array.isArray(input.payload)
    ? input.payload
    : {};

  if (!owner || !coll || !rid) {
    throw new Error("Atomic sync commit requires owner, coll and rid");
  }

  let result = null;
  app.runInTransaction((txApp) => {
    // IMPORTANT: always re-read through txApp. PocketBase documents that only
    // a single writer/transaction is allowed and using the outer app here can
    // deadlock or reintroduce a stale decision.
    const existing = dataAccess.first(
      txApp,
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid}",
      {owner: owner, coll: coll, rid: rid},
    );

    if (existing) {
      const decision = lww.decide(
        existing.getString("stamp"),
        existing.getBool("deleted"),
        stamp,
        deleted,
      );
      if (!decision.apply) {
        result = {
          applied: false,
          stamp: existing.getString("stamp"),
          reason: decision.reason,
        };
        return;
      }
    }

    const collection = txApp.findCollectionByNameOrId("wesios_records");
    const record = existing || new Record(collection);
    // A tombstone carries the last authoritative payload for row-level read
    // policy/migration. If the row appeared after the caller's preflight read,
    // preserve the transaction-current payload rather than writing {}.
    const payload = deleted && existing ? payloadOf(existing) : suppliedPayload;

    record.set("owner", owner);
    record.set("org", org);
    record.set("coll", coll);
    record.set("rid", rid);
    record.set("payload", payload);
    record.set("stamp", stamp);
    record.set("deleted", deleted);
    txApp.save(record);

    result = {
      applied: true,
      stamp: stamp,
      reason: existing ? "updated" : "created",
    };
  });

  if (!result) throw new Error("Atomic sync transaction returned no result");
  return result;
}

module.exports = {
  commit,
  payloadOf,
};
