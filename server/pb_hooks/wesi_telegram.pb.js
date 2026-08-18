// PocketBase serializes each route/cron handler into an isolated JS program.
// Keep this file deliberately thin: every handler loads the reusable gateway
// module inside its own scope instead of closing over top-level functions.

routerAdd("POST", "/api/wesi/telegram/link/create", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.createLink(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/telegram/status", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.status(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/revoke", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.revoke(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/context", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.context(e);
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/telegram/preferences", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.preferences(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/telegram/open", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.open(e);
});

routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.webhook(e);
});

cronAdd("wesios_telegram_alerts_v1", "*/5 * * * *", () => {
  try {
    const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
    gateway.runNotifier($app);
  } catch (_) {}
});
