import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");

function source(name) {
  return fs.readFileSync(path.resolve("server/pb_hooks", name), "utf8");
}

test("remaining internal write/runtime lookups fail closed", () => {
  for (const name of [
    "wesi_ai_calendar_write_tools.js",
    "wesi_ai_knowledge_write_tools.js",
    "wesi_ai_media_lib.js",
    "wesi_ai_remote_worker.pb.js",
    "wesi_ai_lib.js",
  ]) {
    const s = source(name);
    assert.equal(s.includes("findFirstRecordByFilter"), false, name + " still has direct first-record lookup");
    assert.equal(s.includes("wesi_ai_data_access.js"), true, name + " does not use shared data access");
  }
  const worker = source("wesi_ai_remote_worker.pb.js");
  assert.equal(worker.includes("e.app.findRecordsByFilter"), false, "worker list can still fake an empty set");
});

test("connector vault distinguishes missing credentials from vault read failure", () => {
  const vault = require(path.resolve("server/pb_hooks/wesi_ai_connector_vault.js"));
  const ctx = {ownerId: "owner"};
  const empty = {app: {findRecordsByFilter() { return []; }}};
  assert.deepEqual(vault.listCredentials(empty, ctx, "github"), []);
  const broken = {app: {findRecordsByFilter() { throw new Error("db down"); }}};
  assert.throws(
    () => vault.listCredentials(broken, ctx, "github"),
    (error) => error && error.code === "CONNECTOR_VAULT_READ_FAILED",
  );
});

test("GitHub definitions are not hidden by credential metadata reads", () => {
  const s = source("wesi_ai_github_connector.js");
  const start = s.indexOf("function definitions(e, ctx)");
  const end = s.indexOf("function execute(e, ctx", start);
  const body = s.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.equal(body.includes("listCredentials"), false);
  assert.ok(body.includes("if (!vault.ready()) return []"));
  assert.ok(s.includes("errorCode:String((error&&error.code)||\"CONNECTOR_VAULT_READ_FAILED\")"));
});

test("confirmation ticket read reports data unavailable instead of expired", () => {
  globalThis.$security = {
    hs256() { return "binding"; },
  };
  const broker = require(path.resolve("server/pb_hooks/wesi_ai_action_broker.js"));
  const result = broker.confirm(
    {
      app: {findRecordsByFilter() { throw new Error("db down"); }},
      auth: {id: "auth"},
      request: {header: {get() { return "session"; }}},
    },
    {ownerId: "owner", employeeId: "owner"},
    "wai_confirm_1234567890abcdef",
    () => null,
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, "WAI_TOOL_DATA_UNAVAILABLE");
});
