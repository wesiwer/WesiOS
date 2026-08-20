// Deployment retrigger only: force the corrected production sync workflow to run.
// Extended WesiOS sync routes.
//
// Every callback resolves its helper module inside the request. PocketBase can
// keep already-registered callbacks alive across a hot hook reload; closing
// over top-level helper functions or loop variables therefore makes callbacks
// point at stale/undefined JS state. Keep these routes explicit and literal.

routerAdd("GET", "/api/wesi/sync/revision-v2", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.revision(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/sandbox_transactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "sandbox_transactions", "private", "sandbox", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/sandbox_transactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "sandbox_transactions", "private", "sandbox", false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/what_if_presets", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "what_if_presets", "private", "sandbox", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/what_if_presets", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "what_if_presets", "private", "sandbox", false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/profile", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "profile", "private", null, false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/profile", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "profile", "private", null, false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/shield_private", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "shield_private", "private", null, true);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/shield_private", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "shield_private", "private", null, true);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/finance_categories", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/finance_categories", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/team_skills", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "team_skills", "company", ["contacts", "tasks"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/team_skills", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "team_skills", "company", ["contacts", "tasks"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/time_center", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "time_center", "private", null, false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/time_center", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "time_center", "private", null, false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/horizon_predictions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_predictions", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/horizon_predictions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_predictions", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/horizon_learning", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_learning", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/horizon_learning", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_learning", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/horizon_competition", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_competition", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/horizon_competition", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_competition", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/horizon_contracts", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/horizon_contracts", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/task_ai_memory", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "task_ai_memory", "private", ["tasks", "ai"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/task_ai_memory", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "task_ai_memory", "private", ["tasks", "ai"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/audio_extras", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "audio_extras", "company", "audio", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/audio_extras", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "audio_extras", "company", "audio", false);
}, $apis.requireAuth("users"));
