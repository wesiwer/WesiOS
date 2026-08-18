from pathlib import Path

root = Path('.')

# Read route integration.
p = root / 'server/pb_hooks/wesi_sync_read.pb.js'
s = p.read_text(encoding='utf-8')
a = '  if (!moduleAllowed()) return e.json(200, {"items": []});\n\n  const payloadOf = (record) => {'
b = '  if (!moduleAllowed()) return e.json(200, {"items": []});\n  const newCollectionReader = require(`${__hooks}/wesi_sync_new_collection_policy.js`).reader(e, ctx, collection);\n\n  const payloadOf = (record) => {'
if a not in s: raise SystemExit('read module anchor not found')
s = s.replace(a, b, 1)
a = '    if (collection === "organizations" && !ctx.isOwner) {\n      allowed = ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true;'
b = '    if (newCollectionReader) {\n      allowed = newCollectionReader(p, row);\n    } else if (collection === "organizations" && !ctx.isOwner) {\n      allowed = ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true;'
if a not in s: raise SystemExit('read row anchor not found')
p.write_text(s.replace(a, b, 1), encoding='utf-8')

# Write route integration.
p = root / 'server/pb_hooks/wesi_sync_write.pb.js'
s = p.read_text(encoding='utf-8')
a = '  if (privateCollections[collection]) {\n    // Authenticated-account scope is sufficient; records never share owner id\n    // with another employee.'
b = '  const handledByNewPolicy = require(`${__hooks}/wesi_sync_new_collection_policy.js`).assertWrite(\n    e, ctx, collection, incoming, before, existing, deleted,\n  );\n\n  if (handledByNewPolicy) {\n    // New per-record collections are authorized by the shared policy helper.\n  } else if (privateCollections[collection]) {\n    // Authenticated-account scope is sufficient; records never share owner id\n    // with another employee.'
if a not in s: raise SystemExit('write policy anchor not found')
p.write_text(s.replace(a, b, 1), encoding='utf-8')

# Current canonical deploy integration.
p = root / '.github/workflows/deploy-sync-hooks.yml'
s = p.read_text(encoding='utf-8')
replacements = [
("      - 'server/pb_hooks/wesi_sync_data_access_contract_test.mjs'\n", "      - 'server/pb_hooks/wesi_sync_data_access_contract_test.mjs'\n      - 'server/pb_hooks/wesi_sync_new_collection_policy.js'\n      - 'server/pb_hooks/wesi_sync_new_collection_policy_test.mjs'\n"),
("            server/pb_hooks/wesi_sync_data_access.js \\\n            server/pb_hooks/wesi_sync_lww.js", "            server/pb_hooks/wesi_sync_data_access.js \\\n            server/pb_hooks/wesi_sync_new_collection_policy.js \\\n            server/pb_hooks/wesi_sync_lww.js"),
("            server/pb_hooks/wesi_sync_data_access_contract_test.mjs \\\n            server/pb_hooks/wesi_sync_lww_test.mjs", "            server/pb_hooks/wesi_sync_data_access_contract_test.mjs \\\n            server/pb_hooks/wesi_sync_new_collection_policy_test.mjs \\\n            server/pb_hooks/wesi_sync_lww_test.mjs"),
("          grep -q 'wesi_sync_data_access.js' server/pb_hooks/wesi_sync_context.pb.js\n", "          grep -q 'wesi_sync_data_access.js' server/pb_hooks/wesi_sync_context.pb.js\n          grep -q 'wesi_sync_new_collection_policy.js' server/pb_hooks/wesi_sync_read.pb.js\n          grep -q 'wesi_sync_new_collection_policy.js' server/pb_hooks/wesi_sync_write.pb.js\n"),
("            server/pb_hooks/wesi_sync_data_access.js \\\n            server/pb_hooks/wesi_sync_lww.js \\\n            server/pb_hooks/wesi_sync_context.pb.js", "            server/pb_hooks/wesi_sync_data_access.js \\\n            server/pb_hooks/wesi_sync_new_collection_policy.js \\\n            server/pb_hooks/wesi_sync_lww.js \\\n            server/pb_hooks/wesi_sync_context.pb.js"),
("          runtime_files=(wesi_sync_data_access.js wesi_sync_lww.js wesi_sync_extra_runtime.js)", "          runtime_files=(wesi_sync_data_access.js wesi_sync_new_collection_policy.js wesi_sync_lww.js wesi_sync_extra_runtime.js)"),
]
for old, new in replacements:
    if old not in s: raise SystemExit('deploy anchor not found: ' + old.splitlines()[0])
    s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')

# Small route/deploy contract; policy semantics are tested independently below.
t = root / 'server/pb_hooks/wesi_sync_new_collection_policy_test.mjs'
t.write_text(r'''import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";
const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");
globalThis.ForbiddenError = class ForbiddenError extends Error {};
const policy = require(path.resolve("server/pb_hooks/wesi_sync_new_collection_policy.js"));
function row(rid, payload){return {get(n){return n==="payload"?payload:null;},getString(n){return n==="rid"?rid:"";}};}
function app(){const d={crm_clients:[row("mine",{id:"mine",organizationId:"org",ownerEmployeeId:"e1"}),row("other",{id:"other",organizationId:"org",ownerEmployeeId:"e2"})],crm_deals:[row("assigned",{id:"assigned",clientId:"other",organizationId:"org",responsibleEmployeeId:"e1"}),row("foreign",{id:"foreign",clientId:"other",organizationId:"org",responsibleEmployeeId:"e2"})],audio_beats:[row("beat",{id:"beat",authorEmployeeId:"e1"})],file_grants:[]};return {findRecordsByFilter(_c,_f,_s,max,_o,p){const a=d[String(p?.coll||"")]||[];return p?.rid?a.filter(x=>x.getString("rid")===String(p.rid)).slice(0,max||10000):a.slice(0,max||10000);}};}
const ctx={ownerId:"owner",employeeId:"e1",isOwner:false,modules:["crm","audio","roadmap"],allowedOrgIds:{org:true},canManageTeam:false};
test("CRM visibility follows owner/responsible scope",()=>{const e={app:app()};const c=policy.reader(e,ctx,"crm_clients");assert.equal(c({id:"other",organizationId:"org",ownerEmployeeId:"e2"}),true);assert.equal(c({id:"hidden",organizationId:"org",ownerEmployeeId:"e2"}),false);const d=policy.reader(e,ctx,"crm_deals");assert.equal(d({id:"assigned",clientId:"other",organizationId:"org",responsibleEmployeeId:"e1"}),true);assert.equal(d({id:"foreign",clientId:"other",organizationId:"org",responsibleEmployeeId:"e2"}),false);});
test("Roadmap and Audio writes require modules",()=>{const none={...ctx,modules:[]};assert.throws(()=>policy.assertWrite({app:app()},none,"roadmap_projects",{id:"p"},{},null,false),ForbiddenError);assert.throws(()=>policy.assertWrite({app:app()},none,"audio_beats",{id:"b"},{},null,false),ForbiddenError);});
test("CRM cannot cross employee visibility",()=>{const e={app:app()};assert.equal(policy.assertWrite(e,ctx,"crm_clients",{id:"mine",organizationId:"org",ownerEmployeeId:"e1"},{},null,false),true);assert.throws(()=>policy.assertWrite(e,ctx,"crm_clients",{id:"hidden",organizationId:"org",ownerEmployeeId:"e2"},{},null,false),ForbiddenError);});
test("File grants cannot impersonate grantor",()=>{const e={app:app()};const good={id:"g",subjectKind:"beat",subjectId:"beat",employeeId:"e2",grantedBy:"e1"};assert.equal(policy.assertWrite(e,ctx,"file_grants",good,{},null,false),true);assert.throws(()=>policy.assertWrite(e,ctx,"file_grants",{...good,id:"g2",grantedBy:"e9"},{},null,false),ForbiddenError);});
test("owner stays unrestricted",()=>{const owner={...ctx,isOwner:true,employeeId:"owner",modules:[]};assert.equal(policy.assertWrite({app:app()},owner,"crm_clients",{id:"x"},{},null,false),true);assert.equal(policy.reader({app:app()},owner,"file_handovers")({}),true);});
test("routes and atomic deploy include shared policy",()=>{const r=fs.readFileSync("server/pb_hooks/wesi_sync_read.pb.js","utf8");const w=fs.readFileSync("server/pb_hooks/wesi_sync_write.pb.js","utf8");const d=fs.readFileSync(".github/workflows/deploy-sync-hooks.yml","utf8");assert.match(r,/newCollectionReader/);assert.match(w,/handledByNewPolicy/);assert.match(d,/runtime_files=\(wesi_sync_data_access\.js wesi_sync_new_collection_policy\.js/);});
''', encoding='utf-8')

for rel in ['server/pb_hooks/wesi_sync_read.pb.js','server/pb_hooks/wesi_sync_write.pb.js','.github/workflows/deploy-sync-hooks.yml','server/pb_hooks/wesi_sync_new_collection_policy_test.mjs']:
    p=root/rel
    p.write_text('\n'.join(x.rstrip() for x in p.read_text(encoding='utf-8').splitlines())+'\n',encoding='utf-8')
print('CURRENT_SYNC_POLICY_PATCH_READY')
