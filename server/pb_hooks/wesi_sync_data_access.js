function boundedLimit(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return 10000;
  return Math.min(10000, Math.max(1, Math.floor(parsed)));
}

module.exports = {
  records: function(app, collection, filter, sort, maxRecords, offset, params) {
    return app.findRecordsByFilter(
      collection,
      filter,
      sort,
      boundedLimit(maxRecords),
      Number(offset || 0),
      params || {},
    );
  },

  first: function(app, collection, filter, params) {
    const rows = module.exports.records(app, collection, filter, "id", 1, 0, params);
    return rows.length ? rows[0] : null;
  },

  // Some permission checks need the complete auxiliary set (for example all
  // chat envelopes before filtering message rows). PocketBase's single read is
  // intentionally bounded, so iterate stable id-ordered pages instead of
  // silently treating the first 10k rows as the whole database.
  all: function(app, collection, filter, sort, params) {
    const batchSize = 5000;
    let offset = 0;
    const out = [];
    while (true) {
      const rows = module.exports.records(
        app,
        collection,
        filter,
        sort || "id",
        batchSize,
        offset,
        params || {},
      );
      for (const row of rows) out.push(row);
      if (rows.length < batchSize) break;
      offset += rows.length;
    }
    return out;
  },
};
