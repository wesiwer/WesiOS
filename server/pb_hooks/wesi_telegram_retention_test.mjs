import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const retention = require("./wesi_telegram_interactions.js");

assert.equal(retention.RETENTION_TTL_MS, 24 * 60 * 60 * 1000);
assert.equal(retention.RETENTION_COLL, "telegram_retention");
assert.equal(retention.retentionRid("123", 456), "msg:123:456");
assert.equal(
  retention.retentionDueAt("2026-08-18T10:00:00.000Z"),
  "2026-08-19T10:00:00.000Z",
);

console.log("TELEGRAM_RETENTION_24H_OK");
