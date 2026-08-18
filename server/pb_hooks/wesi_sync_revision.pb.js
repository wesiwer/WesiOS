// Collection-level revision invalidation.
//
// This hook is intentionally below every writer. Wesi AI tools and future
// server features may write wesios_records without going through the HTTP sync
// gateway, but clients still have to notice those mutations within the normal
// revision polling interval.

function touchRevision(e) {
  const revision = require(`${__hooks}/wesi_sync_revision.js`);
  if (revision.isMarker(e.record)) return;
  try {
    revision.touch(e.app, e.record.getString("owner"));
  } catch (error) {
    // The business write is already committed because these are AfterSuccess
    // hooks. Revision maintenance is secondary and must never turn that
    // successful mutation into a new application error. Logging itself is
    // therefore best-effort too: PocketBase JSVM logging surfaces can differ
    // between versions/builds.
    try {
      if (typeof console !== "undefined" && console && typeof console.log === "function") {
        console.log("WesiOS sync revision touch failed: " + String(error));
      }
    } catch (_) {}
  }
}

onRecordAfterCreateSuccess((e) => {
  touchRevision(e);
  e.next();
}, "wesios_records");

onRecordAfterUpdateSuccess((e) => {
  touchRevision(e);
  e.next();
}, "wesios_records");

onRecordAfterDeleteSuccess((e) => {
  touchRevision(e);
  e.next();
}, "wesios_records");
