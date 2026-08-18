for (const coll of ["file_requests", "file_grants", "file_handovers"]) {
  routerAdd("GET", "/api/wesi/sync/" + coll, (e) => {
    return require(`${__hooks}/wesi_sync_files_runtime.js`).read(e, coll);
  }, $apis.requireAuth("users"));

  routerAdd("POST", "/api/wesi/sync/" + coll, (e) => {
    return require(`${__hooks}/wesi_sync_files_runtime.js`).write(e, coll);
  }, $apis.requireAuth("users"));
}
