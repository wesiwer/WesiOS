// Fresh versioned routes for the extended WesiOS sync collections.
//
// These paths intentionally differ from the legacy /api/wesi/sync/* routes.
// PocketBase may keep already-registered JS callbacks alive across hot hook
// reloads; registering a new path guarantees that requests reach callbacks
// created from the current hook code without requiring a privileged service
// restart.

routerAdd("GET", "/api/wesi/sync-v3/revision", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.revision(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/sandbox_transactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "sandbox_transactions", "private", "sandbox", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/sandbox_transactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "sandbox_transactions", "private", "sandbox", false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/what_if_presets", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "what_if_presets", "private", "sandbox", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/what_if_presets", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "what_if_presets", "private", "sandbox", false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/profile", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "profile", "private", null, false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/profile", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "profile", "private", null, false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/shield_private", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "shield_private", "private", null, true);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/shield_private", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "shield_private", "private", null, true);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/finance_categories", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/finance_categories", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/team_skills", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "team_skills", "company", ["contacts", "tasks"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/team_skills", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "team_skills", "company", ["contacts", "tasks"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/time_center", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "time_center", "private", null, false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/time_center", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "time_center", "private", null, false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/horizon_predictions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_predictions", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/horizon_predictions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_predictions", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/horizon_learning", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_learning", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/horizon_learning", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_learning", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/horizon_competition", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_competition", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/horizon_competition", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_competition", "private", ["treasury", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/horizon_contracts", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/horizon_contracts", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/task_ai_memory", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "task_ai_memory", "private", ["tasks", "ai"], false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/task_ai_memory", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "task_ai_memory", "private", ["tasks", "ai"], false);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync-v3/audio_extras", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.read(e, "audio_extras", "company", "audio", false);
}, $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync-v3/audio_extras", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_extra_runtime.js`);
  return runtime.write(e, "audio_extras", "company", "audio", false);
}, $apis.requireAuth("users"));
