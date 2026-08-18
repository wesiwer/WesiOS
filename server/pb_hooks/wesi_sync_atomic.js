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

function normalizedInput(input) {
  const out = {
    owner: String(input.owner || "").trim(),
    org: String(input.org || ""),
    coll: String(input.coll || "").trim(),
    rid: String(input.rid || "").trim(),
    stamp: String(input.stamp || ""),
    deleted: input.deleted === true,
    payload: input.payload && typeof input.payload === "object" &&
        !Array.isArray(input.payload)
      ? input.payload
      : {},
  };
  if (!out.owner || !out.coll || !out.rid) {
    throw new Error("Atomic sync write requires owner, coll and rid");
  }
  return out;
}

function currentRow(txApp, input) {
  return dataAccess.first(
    txApp,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid}",
    {owner: input.owner, coll: input.coll, rid: input.rid},
  );
}

function fill(record, input, payload) {
  record.set("owner", input.owner);
  record.set("org", input.org);
  record.set("coll", input.coll);
  record.set("rid", input.rid);
  record.set("payload", payload);
  record.set("stamp", input.stamp);
  record.set("deleted", input.deleted);
}

function commit(app, rawInput) {
  const input = normalizedInput(rawInput);
  let result = null;

  app.runInTransaction((txApp) => {
    // IMPORTANT: always re-read through txApp. PocketBase documents that only
    // a single writer/transaction is allowed and using the outer app here can
    // deadlock or reintroduce a stale decision.
    const existing = currentRow(txApp, input);

    if (existing) {
      const decision = lww.decide(
        existing.getString("stamp"),
        existing.getBool("deleted"),
        input.stamp,
        input.deleted,
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
    const payload = input.deleted && existing
      ? payloadOf(existing)
      : input.payload;
    fill(record, input, payload);
    txApp.save(record);

    result = {
      applied: true,
      stamp: input.stamp,
      reason: existing ? "updated" : "created",
    };
  });

  if (!result) throw new Error("Atomic sync transaction returned no result");
  return result;
}

// Migration-only primitive. Unlike normal LWW commit, an already-existing
// canonical target ALWAYS wins, regardless of timestamps. This prevents a
// late legacy profile_private migration from overwriting profile/me or
// shield_private that a current client has already created.
function createIfAbsent(app, rawInput) {
  const input = normalizedInput(rawInput);
  let result = null;

  app.runInTransaction((txApp) => {
    const existing = currentRow(txApp, input);
    if (existing) {
      result = {
        created: false,
        stamp: existing.getString("stamp"),
      };
      return;
    }

    const collection = txApp.findCollectionByNameOrId("wesios_records");
    const record = new Record(collection);
    fill(record, input, input.payload);
    txApp.save(record);
    result = {created: true, stamp: input.stamp};
  });

  if (!result) {
    throw new Error("Atomic create-if-absent transaction returned no result");
  }
  return result;
}

module.exports = {
  commit,
  createIfAbsent,
  payloadOf,
};
