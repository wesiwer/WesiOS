from pathlib import Path

root = Path('.')

# Integrate reader policy.
path = root / 'server/pb_hooks/wesi_sync_read.pb.js'
text = path.read_text(encoding='utf-8')
anchor = '''  if (!moduleAllowed()) return e.json(200, {"items": []});

  const payloadOf = (record) => {'''
replacement = '''  if (!moduleAllowed()) return e.json(200, {"items": []});
  const newCollectionReader = require(`${__hooks}/wesi_sync_new_collection_policy.js`).reader(e, ctx, collection);

  const payloadOf = (record) => {'''
if anchor not in text:
    raise SystemExit('read policy anchor not found')
text = text.replace(anchor, replacement, 1)

loop_anchor = '''    if (collection === "organizations" && !ctx.isOwner) {
      allowed = ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true;'''
loop_replacement = '''    if (newCollectionReader) {
      allowed = newCollectionReader(p, row);
    } else if (collection === "organizations" && !ctx.isOwner) {
      allowed = ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true;'''
if loop_anchor not in text:
    raise SystemExit('read loop anchor not found')
text = text.replace(loop_anchor, loop_replacement, 1)
path.write_text(text, encoding='utf-8')

# Integrate writer policy before legacy policy branches.
path = root / 'server/pb_hooks/wesi_sync_write.pb.js'
text = path.read_text(encoding='utf-8')
anchor = '''  if (privateCollections[collection]) {
    // Authenticated-account scope is sufficient; records never share owner id
    // with another employee.'''
replacement = '''  const handledByNewPolicy = require(`${__hooks}/wesi_sync_new_collection_policy.js`).assertWrite(
    e, ctx, collection, incoming, before, existing, deleted,
  );

  if (handledByNewPolicy) {
    // New per-record collections are authorized by the shared policy helper.
  } else if (privateCollections[collection]) {
    // Authenticated-account scope is sufficient; records never share owner id
    // with another employee.'''
if anchor not in text:
    raise SystemExit('write policy anchor not found')
text = text.replace(anchor, replacement, 1)
path.write_text(text, encoding='utf-8')

# Ensure canonical sync deploy includes policy helper.
path = root / '.github/workflows/deploy-sync-hooks.yml'
text = path.read_text(encoding='utf-8')
anchor = '''          files=(
            wesi_sync_data_access.js
            wesi_sync_context.pb.js'''
replacement = '''          files=(
            wesi_sync_data_access.js
            wesi_sync_new_collection_policy.js
            wesi_sync_context.pb.js'''
if anchor not in text:
    raise SystemExit('deploy file list anchor not found')
text = text.replace(anchor, replacement, 1)

# Add the new policy test to deployment preflight.
test_anchor = '''          node --test server/pb_hooks/wesi_sync_data_access_contract_test.mjs
          # Critical contracts: session parsing must match security hook.'''
test_replacement = '''          node --test server/pb_hooks/wesi_sync_data_access_contract_test.mjs server/pb_hooks/wesi_sync_new_collection_policy_test.mjs
          # Critical contracts: session parsing must match security hook.'''
if test_anchor not in text:
    raise SystemExit('deploy test anchor not found')
text = text.replace(test_anchor, test_replacement, 1)
path.write_text(text, encoding='utf-8')

# Policy unit + route integration contract.
test = root / 'server/pb_hooks/wesi_sync_new_collection_policy_test.mjs'
test.write_text(r'''import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");
globalThis.ForbiddenError = class ForbiddenError extends Error {};
const policy = require(path.resolve("server/pb_hooks/wesi_sync_new_collection_policy.js"));

function row(rid, payload) {
  return {
    get(name) { return name === "payload" ? payload : null; },
    getString(name) { return name === "rid" ? rid : ""; },
  };
}

function appFixture() {
  const data = {
    crm_clients: [
      row("mine", {id: "mine", organizationId: "org", ownerEmployeeId: "e1"}),
      row("other", {id: "other", organizationId: "org", ownerEmployeeId: "e2"}),
    ],
    crm_deals: [
      row("assigned", {id: "assigned", clientId: "other", organizationId: "org", responsibleEmployeeId: "e1"}),
      row("foreign", {id: "foreign", clientId: "other", organizationId: "org", responsibleEmployeeId: "e2"}),
    ],
    audio_beats: [row("beat-mine", {id: "beat-mine", authorEmployeeId: "e1"})],
    file_grants: [],
  };
  return {
    findRecordsByFilter(_collection, _filter, _sort, max, _offset, params) {
      const rows = data[String(params?.coll || "")] || [];
      if (params?.rid) return rows.filter((item) => item.getString("rid") === String(params.rid)).slice(0, max || 10000);
      return rows.slice(0, max || 10000);
    },
  };
}

const ctx = {
  ownerId: "owner",
  employeeId: "e1",
  isOwner: false,
  modules: ["crm", "audio", "roadmap"],
  allowedOrgIds: {org: true},
  canManageTeam: false,
};

test("CRM per-record visibility matches owner/responsible legacy semantics", () => {
  const readerClients = policy.reader({app: appFixture()}, ctx, "crm_clients");
  assert.equal(readerClients({id: "mine", organizationId: "org", ownerEmployeeId: "e1"}), true);
  // A client is visible when the employee owns an assigned deal for that client.
  assert.equal(readerClients({id: "other", organizationId: "org", ownerEmployeeId: "e2"}), true);
  assert.equal(readerClients({id: "hidden", organizationId: "org", ownerEmployeeId: "e2"}), false);

  const readerDeals = policy.reader({app: appFixture()}, ctx, "crm_deals");
  assert.equal(readerDeals({id: "assigned", clientId: "other", organizationId: "org", responsibleEmployeeId: "e1"}), true);
  assert.equal(readerDeals({id: "foreign", clientId: "other", organizationId: "org", responsibleEmployeeId: "e2"}), false);
});

test("new Roadmap and Audio writes require their modules", () => {
  const noModules = {...ctx, modules: []};
  assert.throws(() => policy.assertWrite({app: appFixture()}, noModules, "roadmap_projects", {id: "p"}, {}, null, false), ForbiddenError);
  assert.throws(() => policy.assertWrite({app: appFixture()}, noModules, "audio_beats", {id: "b"}, {}, null, false), ForbiddenError);
});

test("CRM writes cannot cross employee visibility", () => {
  const e = {app: appFixture()};
  assert.equal(policy.assertWrite(e, ctx, "crm_clients", {id: "mine", organizationId: "org", ownerEmployeeId: "e1"}, {}, null, false), true);
  assert.throws(() => policy.assertWrite(e, ctx, "crm_clients", {id: "hidden", organizationId: "org", ownerEmployeeId: "e2"}, {}, null, false), ForbiddenError);
});

test("FileShare grant cannot impersonate another grantor", () => {
  const e = {app: appFixture()};
  const good = {id: "g1", subjectKind: "beat", subjectId: "beat-mine", employeeId: "e2", grantedBy: "e1"};
  assert.equal(policy.assertWrite(e, ctx, "file_grants", good, {}, null, false), true);
  const bad = {...good, id: "g2", grantedBy: "e9"};
  assert.throws(() => policy.assertWrite(e, ctx, "file_grants", bad, {}, null, false), ForbiddenError);
});

test("owner remains unrestricted for new per-record collections", () => {
  const owner = {...ctx, isOwner: true, employeeId: "owner", modules: []};
  assert.equal(policy.assertWrite({app: appFixture()}, owner, "crm_clients", {id: "x"}, {}, null, false), true);
  assert.equal(policy.reader({app: appFixture()}, owner, "file_handovers")({}), true);
});

test("GET and POST routes cannot bypass shared new-collection policy", () => {
  const read = fs.readFileSync("server/pb_hooks/wesi_sync_read.pb.js", "utf8");
  const write = fs.readFileSync("server/pb_hooks/wesi_sync_write.pb.js", "utf8");
  const deploy = fs.readFileSync(".github/workflows/deploy-sync-hooks.yml", "utf8");
  assert.match(read, /newCollectionReader/);
  assert.match(read, /wesi_sync_new_collection_policy\.js/);
  assert.match(write, /handledByNewPolicy/);
  assert.match(write, /wesi_sync_new_collection_policy\.js/);
  assert.match(deploy, /wesi_sync_new_collection_policy\.js/);
});
''', encoding='utf-8')

for rel in [
    'server/pb_hooks/wesi_sync_read.pb.js',
    'server/pb_hooks/wesi_sync_write.pb.js',
    '.github/workflows/deploy-sync-hooks.yml',
    'server/pb_hooks/wesi_sync_new_collection_policy_test.mjs',
]:
    p = root / rel
    lines = p.read_text(encoding='utf-8').splitlines()
    p.write_text('\n'.join(line.rstrip() for line in lines) + '\n', encoding='utf-8')

print('SYNC_NEW_COLLECTION_POLICY_INTEGRATION_READY')
