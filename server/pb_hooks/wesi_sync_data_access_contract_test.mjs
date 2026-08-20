import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
const access = require(path.resolve("server/pb_hooks/wesi_sync_data_access.js"));

// Keep this contract in the production sync deploy path so a release-side
// compatibility fix can force one verified redeploy without touching data.
test("legacy all-row sync reads are internally paged instead of truncated at 10k", () => {
  const calls = [];
  const app = {
    findRecordsByFilter(...args) {
      calls.push(args);
      const limit = args[3];
      const offset = args[4];
      if (offset === 0) return Array.from({length: limit}, (_, i) => ({id: i}));
      if (offset === limit) return Array.from({length: 7}, (_, i) => ({id: limit + i}));
      return [];
    },
  };

  const zero = access.records(
    app,
    "wesios_records",
    "owner='x'",
    "id",
    0,
    0,
    {},
  );
  assert.equal(zero.length, 5007);
  assert.equal(calls[0][3], 5000);
  assert.equal(calls[0][4], 0);
  assert.equal(calls[1][3], 5000);
  assert.equal(calls[1][4], 5000);

  calls.length = 0;
  const legacyTenThousand = access.records(
    app,
    "wesios_records",
    "owner='x'",
    "id",
    10000,
    0,
    {},
  );
  assert.equal(legacyTenThousand.length, 5007);
  assert.equal(calls.length, 2);
});

test("invalid negative sync read limit remains bounded", () => {
  const calls = [];
  const app = {
    findRecordsByFilter(...args) { calls.push(args); return []; },
  };
  access.records(app, "wesios_records", "owner='x'", "id", -5, 0, {});
  assert.equal(calls[0][3], 10000);
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
