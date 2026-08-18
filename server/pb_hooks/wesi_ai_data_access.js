function unavailable(error) {
  const wrapped = new Error("WesiOS tool data read failed");
  wrapped.wesiCode = "WAI_TOOL_DATA_UNAVAILABLE";
  wrapped.wesiMessage = "Не удалось прочитать данные WesiOS";
  if (error) wrapped.cause = error;
  return wrapped;
}

module.exports = {
  records: function(app, collection, filter, sort, maxRecords, offset, params) {
    try {
      return app.findRecordsByFilter(collection, filter, sort, maxRecords, offset, params);
    } catch (error) {
      throw unavailable(error);
    }
  },

  first: function(app, collection, filter, params) {
    const rows = module.exports.records(app, collection, filter, "id", 1, 0, params);
    return rows.length ? rows[0] : null;
  },
};
