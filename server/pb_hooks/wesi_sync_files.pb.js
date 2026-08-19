// File exchange sync routes.
//
// PocketBase JS route callbacks are executed in isolated handler contexts.
// Never close over a top-level loop variable here: a callback registered from
// `for (const coll of ...)` may later execute with `coll` undefined and the
// client receives PocketBase's generic HTTP 400. Keep every route explicit and
// resolve the runtime module from inside the handler.

routerAdd("GET", "/api/wesi/sync/file_grants", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.read(e, "file_grants");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/file_grants", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.write(e, "file_grants");
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/file_requests", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.read(e, "file_requests");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/file_requests", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.write(e, "file_requests");
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/file_handovers", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.read(e, "file_handovers");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/file_handovers", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_files_runtime.js`);
  return runtime.write(e, "file_handovers");
}, $apis.requireAuth("users"));
