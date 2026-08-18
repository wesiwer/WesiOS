// PocketBase serializes each route/cron handler into an isolated JS program.
// Keep this file deliberately thin: every handler loads reusable modules
// inside its own scope instead of closing over top-level functions.

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

routerAdd("POST", "/api/wesi/telegram/test-push", (e) => {
  const experience = require(`${__hooks}/wesi_telegram_experience.js`);
  return experience.testPush(e);
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/telegram/open", (e) => {
  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.open(e);
});

routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {
  // Capture the exact incoming message id and opportunistically remove any
  // WesiOS chat messages whose 24-hour retention window has expired.
  // captureIncoming authenticates the Telegram secret again before touching
  // the retention queue, so spoofed public requests cannot enqueue deletes.
  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    interactions.captureIncoming(e);
  } catch (_) {}

  // Experience preprocessing records private message ids, adds contextual
  // visuals and can consume updates from users that have been offboarded.
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    const preflight = experience.beforeWebhook(e);
    if (preflight && preflight.handled === true) {
      return e.json(200, {ok: true});
    }
  } catch (_) {}

  // Small interaction layer handles actions that intentionally don't belong
  // to the business command gateway, such as a real Telegram push-channel test.
  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    const interaction = interactions.handle(e);
    if (interaction && interaction.handled === true) {
      return e.json(200, {ok: true});
    }
  } catch (_) {}

  const gateway = require(`${__hooks}/wesi_telegram_gateway.js`);
  return gateway.webhook(e);
});

cronAdd("wesios_telegram_alerts_v2", "*/5 * * * *", () => {
  // Retention runs before new alerts so a due message is removed before a new
  // push is sent. New outgoing messages receive their own +24h deadline.
  try {
    const interactions = require(`${__hooks}/wesi_telegram_interactions.js`);
    interactions.cleanupRetention($app);
  } catch (_) {}
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.runNotifier($app);
  } catch (_) {}
  // Morning delivery checks each linked employee's timezone and only sends
  // once per local calendar day during the 08:00 hour. The speaker alternates
  // deterministically: Nirvana -> Zane -> Nirvana -> Zane.
  try {
    const morning = require(`${__hooks}/wesi_telegram_morning.js`);
    morning.runMorning($app);
  } catch (_) {}
});

// Employee Portal revocation deletes the employee auth user. Revoking the
// Telegram link here closes bot access immediately after the DB deletion has
// actually committed.
onRecordAfterDeleteSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.offboardByAuth(e.app, e.record.id, "employee-account-deleted");
  } catch (_) {}
  e.next();
}, "users");

// Sync may represent dismissal/deactivation as a soft-deleted or inactive
// employees record. Cover that path too, without reacting to ordinary edits.
onRecordAfterUpdateSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.handleEmployeeRecord(e.app, e.record, false);
  } catch (_) {}
  e.next();
}, "wesios_records");

onRecordAfterDeleteSuccess((e) => {
  try {
    const experience = require(`${__hooks}/wesi_telegram_experience.js`);
    experience.handleEmployeeRecord(e.app, e.record, true);
  } catch (_) {}
  e.next();
}, "wesios_records");
