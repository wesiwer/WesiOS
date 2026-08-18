function boundedLimit(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return 10000;
  return Math.min(10000, Math.max(1, Math.floor(parsed)));
}

function rawRecords(app, collection, filter, sort, maxRecords, offset, params) {
  return app.findRecordsByFilter(
    collection,
    filter,
    sort,
    boundedLimit(maxRecords),
    Number(offset || 0),
    params || {},
  );
}

function allRecords(app, collection, filter, sort, offset, params) {
  const batchSize = 5000;
  let cursor = Number(offset || 0);
  const out = [];
  while (true) {
    const rows = rawRecords(
      app,
      collection,
      filter,
      sort || "id",
      batchSize,
      cursor,
      params || {},
    );
    for (const row of rows) out.push(row);
    if (rows.length < batchSize) break;
    cursor += rows.length;
  }
  return out;
}

module.exports = {
  records: function(app, collection, filter, sort, maxRecords, offset, params) {
    const requested = Number(maxRecords);

    // In PocketBase sync hooks `0` historically meant "all rows", and the
    // old gateway also used an explicit 10000 as a defensive stand-in for
    // "all". Returning only that first chunk makes a successful Sync silently
    // incomplete once a company crosses the threshold. Preserve the semantic
    // intent, but implement it as bounded database pages rather than one
    // unbounded query.
    if (requested === 0 || requested === 10000) {
      return allRecords(app, collection, filter, sort, offset, params);
    }

    return rawRecords(
      app,
      collection,
      filter,
      sort,
      maxRecords,
      offset,
      params,
    );
  },

  first: function(app, collection, filter, params) {
    const rows = rawRecords(app, collection, filter, "id", 1, 0, params);
    return rows.length ? rows[0] : null;
  },

  all: function(app, collection, filter, sort, params) {
    return allRecords(app, collection, filter, sort, 0, params);
  },
};
