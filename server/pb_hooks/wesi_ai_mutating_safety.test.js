const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const HOOKS = __dirname;
global.__hooks = HOOKS;

const registry = require(path.join(HOOKS, 'wesi_ai_capability_registry.js'));
const toolsSource = fs.readFileSync(path.join(HOOKS, 'wesi_ai_tools.js'), 'utf8');
const block = toolsSource.match(/function adapters\(\)\s*\{[\s\S]*?return\s*\[([\s\S]*?)\];\s*\}/);
assert.ok(block, 'Cannot find Wesi AI adapters registry');
const adapterFiles = [...block[1].matchAll(/require\(base\s*\+\s*["']([^"']+)["']\)/g)].map((m) => m[1]);

function withConnectedGithub(fn) {
  const vault = require(path.join(HOOKS, 'wesi_ai_connector_vault.js'));
  const ready = vault.ready;
  const list = vault.listCredentials;
  vault.ready = () => true;
  vault.listCredentials = () => [{credentialId: 'audit-github', status: 'active', provider: 'github', scopes: []}];
  try { return fn(); } finally { vault.ready = ready; vault.listCredentials = list; }
}

function harness() {
  const state = {saves: 0, deletes: 0};
  const app = {
    findRecordsByFilter() { return []; },
    findFirstRecordByFilter() { return null; },
    findRecordById() { return null; },
    findCollectionByNameOrId() { return {}; },
    save() { state.saves += 1; },
    delete() { state.deletes += 1; },
  };
  return {
    state,
    event: {app, auth: {id: 'audit-auth'}, request: {header: {get() { return ''; }}}},
    ctx: {
      ownerId: 'audit-owner', employeeId: 'audit-owner', isOwner: true,
      modules: ['tasks','treasury','finance','organizations','contacts','calendar','knowledge','crm','roadmap','audio','horizon','presentation','media','connectors','github','ai'],
    },
  };
}

function definitions(file, adapter, e, ctx) {
  if (file === 'wesi_ai_github_connector.js') return withConnectedGithub(() => adapter.definitions(e, ctx));
  return adapter.definitions(e, ctx);
}

test('empty WRITE/DESTRUCTIVE calls fail closed and cannot write', () => {
  for (const file of adapterFiles) {
    const adapter = require(path.join(HOOKS, file));
    const {event, ctx, state} = harness();
    const defs = definitions(file, adapter, event, ctx);
    for (const def of defs) {
      const cap = registry.get(def.name);
      if (!cap || cap.risk === 'READ') continue;
      const beforeSaves = state.saves;
      const beforeDeletes = state.deletes;
      let result;
      assert.doesNotThrow(() => {
        result = adapter.execute(event, ctx, def.name, {}, '', {audit: true});
      }, `${file}/${def.name}: empty call threw instead of failing closed`);
      assert.ok(result && typeof result === 'object' && !Array.isArray(result), `${def.name}: missing structured result`);
      assert.equal(result.ok, false, `${def.name}: empty mutating call unexpectedly succeeded`);
      assert.equal(typeof result.code, 'string', `${def.name}: rejection must include code`);
      assert.equal(typeof result.message, 'string', `${def.name}: rejection must include message`);
      assert.equal(state.saves, beforeSaves, `${def.name}: empty call wrote a PocketBase record`);
      assert.equal(state.deletes, beforeDeletes, `${def.name}: empty call deleted a PocketBase record`);
    }
  }
});
