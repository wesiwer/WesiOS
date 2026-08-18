import assert from "node:assert/strict";
import {createRequire} from "node:module";
import path from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const lww = require(path.resolve("server/pb_hooks/wesi_sync_lww.js"));

const oldStamp = "2026-08-18T00:00:00.000Z";
const sameStamp = "2026-08-18T00:00:01.000Z";
const newStamp = "2026-08-18T00:00:02.000Z";

test("newer incoming row is accepted", () => {
  assert.deepEqual(lww.decide(oldStamp, false, newStamp, false), {
    apply: true,
    reason: "newer",
  });
});

test("late stale request cannot overwrite newer server row", () => {
  assert.deepEqual(lww.decide(newStamp, false, oldStamp, false), {
    apply: false,
    reason: "stale",
  });
});

test("deletion wins an exact timestamp tie", () => {
  assert.equal(lww.decide(sameStamp, false, sameStamp, true).apply, true);
  assert.equal(lww.decide(sameStamp, true, sameStamp, false).apply, false);
});

test("existing server row is authoritative on equal live timestamps", () => {
  assert.deepEqual(lww.decide(sameStamp, false, sameStamp, false), {
    apply: false,
    reason: "tie-existing-authoritative",
  });
});

test("valid incoming row repairs an invalid historical server stamp", () => {
  assert.equal(lww.decide("broken", false, newStamp, false).apply, true);
});
