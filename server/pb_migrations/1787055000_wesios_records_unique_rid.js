/// Makes the sync identity physically unique in SQLite.
///
/// All client/server LWW logic assumes exactly one authoritative row for
/// (owner, coll, rid). Fresh installations already get this index from
/// setup-collections.sh, but old/live collections that existed before that
/// script only had their API rules repaired and could still have no index.
/// Two simultaneous first-writes could therefore create duplicate rows.
///
/// The migration is transactional. First collapse any historical duplicates
/// using the same ordering as WesiOS LWW, then persist the unique index.
migrate((app) => {
  const rows = arrayOf(new DynamicModel({
    id: "",
    owner: "",
    coll: "",
    rid: "",
    stamp: "",
    deleted: false,
  }));

  app.db()
    .newQuery(
      "SELECT id, owner, coll, rid, stamp, deleted " +
      "FROM wesios_records ORDER BY owner, coll, rid, id"
    )
    .all(rows);

  const millis = (raw) => {
    const value = Date.parse(String(raw || ""));
    return Number.isFinite(value) ? value : null;
  };

  const better = (candidate, current) => {
    const a = millis(candidate.stamp);
    const b = millis(current.stamp);

    if (a != null && b == null) return true;
    if (a == null && b != null) return false;
    if (a != null && b != null) {
      if (a > b) return true;
      if (a < b) return false;
    }

    // Same/invalid timestamp: keep the normal WesiOS tie rule.
    if (candidate.deleted === true && current.deleted !== true) return true;
    if (candidate.deleted !== true && current.deleted === true) return false;

    // Both variants are equally authoritative by protocol. Pick a stable row
    // so migration result never depends on SQLite scan order.
    return String(candidate.id) < String(current.id);
  };

  const winners = {};
  const duplicates = [];
  for (const row of rows) {
    const key = String(row.owner) + "\u0000" +
      String(row.coll) + "\u0000" + String(row.rid);
    const current = winners[key];
    if (!current) {
      winners[key] = row;
      continue;
    }
    if (better(row, current)) {
      duplicates.push(current.id);
      winners[key] = row;
    } else {
      duplicates.push(row.id);
    }
  }

  for (const id of duplicates) {
    app.db()
      .newQuery("DELETE FROM wesios_records WHERE id={:id}")
      .bind({id: String(id)})
      .execute();
  }

  const collection = app.findCollectionByNameOrId("wesios_records");
  collection.addIndex(
    "idx_wesios_rid",
    true,
    "owner, coll, rid",
    "",
  );
  app.save(collection);
}, (app) => {
  // Intentionally no destructive downgrade. Re-allowing duplicate sync
  // identities would reintroduce ambiguous authoritative state.
  console.log("wesios_records unique sync identity downgrade is disabled");
});
