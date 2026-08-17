import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
const access = require(path.resolve("server/pb_hooks/wesi_sync_data_access.js"));

test("zero and invalid sync read limits are converted to a bounded positive read", () => {
  const calls = [];
  const app = {
    findRecordsByFilter(...args) { calls.push(args); return []; },
  };
  access.records(app, "wesios_records", "owner='x'", "id", 0, 0, {});
  access.records(app, "wesios_records", "owner='x'", "id", -5, 0, {});
  assert.equal(calls[0][3], 10000);
  assert.equal(calls[1][3], 10000);
});

test("missing row and backend failure are different sync states", () => {
  const empty = {findRecordsByFilter() { return []; }};
  assert.equal(access.first(empty, "wesios_records", "rid='missing'", {}), null);

  const broken = {findRecordsByFilter() { throw new Error("db unavailable"); }};
  assert.throws(() => access.records(broken, "wesios_records", "id != ''", "id", 10, 0, {}), /db unavailable/);
  assert.throws(() => access.first(broken, "wesios_records", "rid='x'", {}), /db unavailable/);
});

test("all production sync gateway reads use the shared fail-closed contract", () => {
  const files = [
    "wesi_sync_context.pb.js",
    "wesi_sync_read.pb.js",
    "wesi_sync_write.pb.js",
    "wesi_sync_extra_runtime.js",
  ];
  for (const name of files) {
    const source = fs.readFileSync(path.resolve("server/pb_hooks", name), "utf8");
    assert.equal(source.includes("e.app.findRecordsByFilter"), false, name);
    assert.equal(source.includes("e.app.findFirstRecordByFilter"), false, name);
    assert.equal(source.includes("wesi_sync_data_access.js"), true, name);
  }
});
