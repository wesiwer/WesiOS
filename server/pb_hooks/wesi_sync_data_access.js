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
};
