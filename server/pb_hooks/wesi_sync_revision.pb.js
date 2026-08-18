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
    // hooks. Never turn a successful user mutation into an apparent failure
    // just because revision maintenance had a transient problem; log it so
    // deployment/monitoring can catch the degraded live-sync signal.
    console.log("WesiOS sync revision touch failed: " + String(error));
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
