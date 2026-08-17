from pathlib import Path

ROOT = Path('server/pb_hooks')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one anchor, got {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def prepend_once(path: Path, line: str) -> None:
    text = path.read_text(encoding='utf-8')
    if line in text:
        return
    path.write_text(line + '\n' + text, encoding='utf-8')


DATA_REQUIRE = 'const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");'

# Calendar write: DB outage must not look like a missing event.
p = ROOT / 'wesi_ai_calendar_write_tools.js'
prepend_once(p, DATA_REQUIRE)
replace_once(
    p,
'''function recordById(e, ctx, id) {
  try {
    return e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='calendar_events' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: id},
    );
  } catch (_) { return null; }
}''',
'''function recordById(e, ctx, id) {
  return dataAccess.first(
    e.app,
    "wesios_records",
    "owner={:owner} && coll='calendar_events' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: id},
  );
}''',
    'calendar recordById',
)

# Knowledge write: do not translate employee/article read failures into empty
# permissions or NOT_FOUND.
p = ROOT / 'wesi_ai_knowledge_write_tools.js'
prepend_once(p, DATA_REQUIRE)
replace_once(
    p,
'''  let employee = null;
  try {
    employee = e.app.findFirstRecordByFilter(
      "wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: ctx.employeeId},
    );
  } catch (_) { employee = null; }''',
'''  const employee = dataAccess.first(
    e.app,
    "wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: ctx.employeeId},
  );''',
    'knowledge employee permissions',
)
replace_once(
    p,
'''function byId(e, ctx, id) {
  try {
    return e.app.findFirstRecordByFilter(
      "wesios_records", "owner={:owner} && coll='articles' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: id},
    );
  } catch (_) { return null; }
}''',
'''function byId(e, ctx, id) {
  return dataAccess.first(
    e.app,
    "wesios_records", "owner={:owner} && coll='articles' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: id},
  );
}''',
    'knowledge article lookup',
)

# Confirmation ticket: cleanup remains deliberately best-effort, but the actual
# ticket read must distinguish missing from backend unavailable.
p = ROOT / 'wesi_ai_action_broker.js'
replace_once(
    p,
'''    let record = null;
    try {
      record = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, coll: CONFIRMATION_COLL, rid: id},
      );
    } catch (_) { record = null; }''',
'''    let record = null;
    try {
      record = require(modulePath("wesi_ai_data_access.js")).first(
        e.app,
        "wesios_records",
        "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, coll: CONFIRMATION_COLL, rid: id},
      );
    } catch (error) {
      return {
        ok: false,
        code: String((error && error.wesiCode) || "WAI_TOOL_DATA_UNAVAILABLE"),
        message: String((error && error.wesiMessage) || "Не удалось прочитать данные WesiOS"),
      };
    }''',
    'confirmation ticket lookup',
)

# Connector vault: a missing row is normal; a query failure is not. Use a
# bounded list query to distinguish the two and raise a connector-safe code.
p = ROOT / 'wesi_ai_connector_vault.js'
replace_once(
    p,
'''function findRecord(e, ctx, rid) {
  try {
    return e.app.findFirstRecordByFilter(COLLECTION, "owner={:owner} && rid={:rid}", {owner: owner(ctx), rid: String(rid || "")});
  } catch (_) { return null; }
}''',
'''function readRows(e, filter, sort, limit, params) {
  try {
    return e.app.findRecordsByFilter(
      COLLECTION,
      filter,
      sort,
      Math.max(1, Math.min(Number(limit || 100), 1000)),
      0,
      params,
    );
  } catch (_) {
    throw new ConnectorVaultError("CONNECTOR_VAULT_READ_FAILED", "Connector credential vault could not be read");
  }
}

function findRecord(e, ctx, rid) {
  const rows = readRows(
    e,
    "owner={:owner} && rid={:rid}",
    "id",
    1,
    {owner: owner(ctx), rid: String(rid || "")},
  );
  return rows.length ? rows[0] : null;
}''',
    'connector vault findRecord',
)
replace_once(
    p,
'''function listCredentials(e, ctx, provider) {
  let records = [];
  try {
    records = e.app.findRecordsByFilter(COLLECTION, "owner={:owner} && kind='credential' && provider={:provider}", "-stamp", 100, 0, {owner: owner(ctx), provider: String(provider || "")});
  } catch (_) { return []; }
  const out = [];''',
'''function listCredentials(e, ctx, provider) {
  const records = readRows(
    e,
    "owner={:owner} && kind='credential' && provider={:provider}",
    "-stamp",
    100,
    {owner: owner(ctx), provider: String(provider || "")},
  );
  const out = [];''',
    'connector vault listCredentials',
)

# GitHub tools should not disappear merely because credential metadata could
# not be read while definitions are being assembled. Expose tools whenever the
# encrypted vault itself is configured; execution returns a concrete credential
# error when no usable account exists.
p = ROOT / 'wesi_ai_github_connector.js'
replace_once(
    p,
'''function definitions(e, ctx) {
  try {
    if (!vault.ready() || !vault.listCredentials(e, ctx, "github").some((c) => c.status === "active")) return [];
  } catch (_) { return []; }
  const cred = {type: "string", description: "Logical GitHub credential id from runtime context; omit only when exactly one account is connected."};''',
'''function definitions(e, ctx) {
  if (!vault.ready()) return [];
  const cred = {type: "string", description: "Logical GitHub credential id from runtime context; omit only when exactly one account is connected."};''',
    'github definitions',
)
replace_once(
    p,
'''  context: (e,ctx) => { let accounts=[]; try{accounts=listMetadata(e,ctx).filter((x)=>x.status==="active");}catch(_){} return {connectors:{github:{connected:accounts.length>0,accounts}}}; },''',
'''  context: (e,ctx) => {
    if (!vault.ready()) {
      return {connectors:{github:{connected:false,accounts:[],errorCode:"CONNECTOR_VAULT_NOT_CONFIGURED"}}};
    }
    try {
      const accounts=listMetadata(e,ctx).filter((x)=>x.status==="active");
      return {connectors:{github:{connected:accounts.length>0,accounts,errorCode:null}}};
    } catch (error) {
      return {connectors:{github:{connected:false,accounts:[],errorCode:String((error&&error.code)||"CONNECTOR_VAULT_READ_FAILED")}}};
    }
  },''',
    'github context',
)

# Media job status: DB outage must not be reported as a nonexistent job.
p = ROOT / 'wesi_ai_media_lib.js'
prepend_once(p, DATA_REQUIRE)
replace_once(
    p,
'''function findJob(jobId) {
  const id = safeJobId(jobId);
  if (!id) return null;
  try {
    return $app.findFirstRecordByFilter(
      "wesios_records",
      "coll='ai_media' && rid={:rid} && deleted=false",
      {rid: "media:" + id}
    );
  } catch (_) {
    return null;
  }
}''',
'''function findJob(jobId) {
  const id = safeJobId(jobId);
  if (!id) return null;
  return dataAccess.first(
    $app,
    "wesios_records",
    "coll='ai_media' && rid={:rid} && deleted=false",
    {rid: "media:" + id},
  );
}''',
    'media findJob',
)

# Remote Worker is part of the Wesi AI tool/runtime surface. Worker absence is a
# legitimate empty query; backend failure must propagate instead of returning
# an empty worker/mailbox set.
p = ROOT / 'wesi_ai_remote_worker.pb.js'
prepend_once(p, 'const dataAccess = require(`${__hooks}/wesi_ai_data_access.js`);')
replace_once(
    p,
'''function findRecord(app, ownerId, coll, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
      {owner: ownerId, coll: coll, rid: rid},
    );
  } catch (_) { return null; }
}

function findRecordAnyOwner(app, coll, rid) {
  try {
    return app.findFirstRecordByFilter(
      "wesios_records",
      "coll={:coll} && rid={:rid} && deleted=false",
      {coll: coll, rid: rid},
    );
  } catch (_) { return null; }
}

function rowsForWorker(app, ownerId, coll, workerId, limit) {
  try {
    return app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && org={:worker} && deleted=false",
      "stamp",
      Math.max(1, Math.min(Number(limit || MAX_MESSAGES_PER_WORKER), MAX_MESSAGES_PER_WORKER)),
      0,
      {owner: ownerId, coll: coll, worker: workerId},
    );
  } catch (_) { return []; }
}''',
'''function findRecord(app, ownerId, coll, rid) {
  return dataAccess.first(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
    {owner: ownerId, coll: coll, rid: rid},
  );
}

function findRecordAnyOwner(app, coll, rid) {
  return dataAccess.first(
    app,
    "wesios_records",
    "coll={:coll} && rid={:rid} && deleted=false",
    {coll: coll, rid: rid},
  );
}

function rowsForWorker(app, ownerId, coll, workerId, limit) {
  return dataAccess.records(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && org={:worker} && deleted=false",
    "stamp",
    Math.max(1, Math.min(Number(limit || MAX_MESSAGES_PER_WORKER), MAX_MESSAGES_PER_WORKER)),
    0,
    {owner: ownerId, coll: coll, worker: workerId},
  );
}''',
    'remote worker data helpers',
)
replace_once(
    p,
'''  const rows = (() => {
    try {
      return e.app.findRecordsByFilter(
        "wesios_records",
        "owner={:owner} && coll={:coll} && deleted=false",
        "stamp",
        64,
        0,
        {owner: ctx.ownerId, coll: COLL_HEARTBEAT},
      );
    } catch (_) { return []; }
  })();''',
'''  const rows = dataAccess.records(
    e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && deleted=false",
    "stamp",
    64,
    0,
    {owner: ctx.ownerId, coll: COLL_HEARTBEAT},
  );''',
    'remote worker heartbeat list',
)

# Wesi AI identity resolution: absence may mean unauthenticated/unlinked, but a
# database failure must not be transformed into the same result.
p = ROOT / 'wesi_ai_lib.js'
prepend_once(p, DATA_REQUIRE)
for label, old, new in [
    (
        'ai lib session',
'''    let session = null;
    try {
      session = e.app.findFirstRecordByFilter("wesios_records", "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false", {rid: "session:" + sid});
    } catch (_) { session = null; }''',
'''    const session = dataAccess.first(e.app, "wesios_records", "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false", {rid: "session:" + sid});''',
    ),
    (
        'ai lib owner marker',
'''    let ownerMarker = null;
    try {
      ownerMarker = e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false", {owner: e.auth.id});
    } catch (_) { ownerMarker = null; }''',
'''    const ownerMarker = dataAccess.first(e.app, "wesios_records", "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false", {owner: e.auth.id});''',
    ),
    (
        'ai lib employee link',
'''    let link = null;
    try {
      link = e.app.findFirstRecordByFilter("wesios_records", "coll='system' && rid={:rid} && deleted=false", {rid: "portal-account:" + e.auth.id});
    } catch (_) { link = null; }''',
'''    const link = dataAccess.first(e.app, "wesios_records", "coll='system' && rid={:rid} && deleted=false", {rid: "portal-account:" + e.auth.id});''',
    ),
    (
        'ai lib employee record',
'''    let employee = null;
    try {
      employee = e.app.findFirstRecordByFilter("wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false", {owner: ownerId, rid: employeeId});
    } catch (_) { employee = null; }''',
'''    const employee = dataAccess.first(e.app, "wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false", {owner: ownerId, rid: employeeId});''',
    ),
]:
    replace_once(p, old, new, label)

# Source-level regression: protect the exact false-empty/false-not-found paths
# repaired above. Best-effort cleanup/parsing catches are intentionally not
# prohibited globally.
test = ROOT / 'wesi_ai_remaining_data_contract_test.mjs'
test.write_text(r'''import assert from "node:assert/strict";
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
''', encoding='utf-8')

# Normalize trailing whitespace so git diff --check remains a hard gate.
for path in [
    ROOT / 'wesi_ai_calendar_write_tools.js',
    ROOT / 'wesi_ai_knowledge_write_tools.js',
    ROOT / 'wesi_ai_action_broker.js',
    ROOT / 'wesi_ai_connector_vault.js',
    ROOT / 'wesi_ai_github_connector.js',
    ROOT / 'wesi_ai_media_lib.js',
    ROOT / 'wesi_ai_remote_worker.pb.js',
    ROOT / 'wesi_ai_lib.js',
    test,
]:
    lines = path.read_text(encoding='utf-8').splitlines()
    path.write_text('\n'.join(line.rstrip() for line in lines) + '\n', encoding='utf-8')

print('AI_REMAINING_DATA_CONTRACT_PATCH_READY')
