import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");
const dataAccess = require(path.resolve("server/pb_hooks/wesi_ai_data_access.js"));
const broker = require(path.resolve("server/pb_hooks/wesi_ai_action_broker.js"));

const internalAdapters = [
  "wesi_ai_audio_tools.js",
  "wesi_ai_crm_write_tools.js",
  "wesi_ai_finance_policy.js",
  "wesi_ai_finance_write_tools.js",
  "wesi_ai_knowledge_tools.js",
  "wesi_ai_roadmap_tools.js",
  "wesi_ai_task_tools.js",
  "wesi_ai_task_write_tools.js",
  "wesi_ai_team_tools.js",
  "wesi_ai_workspace_tools.js",
];

test("shared data helper distinguishes empty rows from backend failure", () => {
  const empty = {findRecordsByFilter() { return []; }};
  assert.deepEqual(dataAccess.records(empty, "wesios_records", "id != ''", "id", 10, 0, {}), []);
  assert.equal(dataAccess.first(empty, "wesios_records", "id='missing'", {}), null);

  const broken = {findRecordsByFilter() { throw new Error("db down"); }};
  assert.throws(
    () => dataAccess.records(broken, "wesios_records", "id != ''", "id", 10, 0, {}),
    (error) => error && error.wesiCode === "WAI_TOOL_DATA_UNAVAILABLE",
  );
});

test("action broker preserves safe tagged tool failures", () => {
  const adapter = {
    execute() {
      const error = new Error("private db error");
      error.wesiCode = "WAI_TOOL_DATA_UNAVAILABLE";
      error.wesiMessage = "Не удалось прочитать данные WesiOS";
      throw error;
    },
  };
  const result = broker.execute(
    {app: {}},
    {ownerId: "owner", employeeId: "owner", isOwner: true},
    adapter,
    "tasks_list",
    {},
    "org_wesi_inc",
    {persona: "zane", conversationId: "c", requestId: "r"},
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, "WAI_TOOL_DATA_UNAVAILABLE");
  assert.equal(result.message, "Не удалось прочитать данные WesiOS");
});

test("internal tool adapters cannot silently convert DB failures to empty state", () => {
  for (const name of internalAdapters) {
    const source = fs.readFileSync(path.resolve("server/pb_hooks", name), "utf8");
    assert.equal(source.includes("e.app.findRecordsByFilter"), false, name + " has a direct records read");
    assert.equal(source.includes("e.app.findFirstRecordByFilter"), false, name + " has a direct first-record read");
    assert.equal(source.includes("wesi_ai_data_access.js"), true, name + " does not use shared data access");
  }
});
