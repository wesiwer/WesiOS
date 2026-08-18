// Exact per-record CRM routes.
//
// Do not let these collections fall through to the generic sync gateway: CRM
// has employee ownership/responsibility rules in addition to module + org
// access. The shared runtime enforces the same scope for GET and POST.

routerAdd("GET", "/api/wesi/sync/crm_clients", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.read(e, "crm_clients");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/crm_clients", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.write(e, "crm_clients");
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/crm_deals", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.read(e, "crm_deals");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/crm_deals", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.write(e, "crm_deals");
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/crm_interactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.read(e, "crm_interactions");
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/sync/crm_interactions", (e) => {
  const runtime = require(`${__hooks}/wesi_sync_crm_runtime.js`);
  return runtime.write(e, "crm_interactions");
}, $apis.requireAuth("users"));
