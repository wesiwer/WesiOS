const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const HOOKS = path.resolve(__dirname, '../pb_hooks');
global.__hooks = HOOKS;
const toolsPath = path.join(HOOKS, 'wesi_ai_tools.js');
const registryPath = path.join(HOOKS, 'wesi_ai_capability_registry.js');
const registry = require(registryPath);
const riskPolicy = require(path.join(HOOKS, 'wesi_ai_risk_policy.js'));

function auditTest(name, fn) {
  test(name, () => {
    try {
      return fn();
    } catch (error) {
      const message = String(error && error.message || error || 'Unknown Wesi AI tool audit failure')
        .replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
      console.error(`::error title=Wesi AI tool audit::${message}`);
      throw error;
    }
  });
}

function adapterFiles() {
  const source = fs.readFileSync(toolsPath, 'utf8');
  const block = source.match(/function adapters\(\)\s*\{[\s\S]*?return\s*\[([\s\S]*?)\];\s*\}/);
  assert.ok(block, 'Cannot find adapters() registry in wesi_ai_tools.js');
  return [...block[1].matchAll(/require\(base\s*\+\s*["']([^"']+)["']\)/g)]
    .map((match) => match[1]);
}

function withConnectedGithub(fn) {
  const vault = require(path.join(HOOKS, 'wesi_ai_connector_vault.js'));
  const originalReady = vault.ready;
  const originalList = vault.listCredentials;
  vault.ready = () => true;
  vault.listCredentials = () => [{credentialId: 'audit-github', status: 'active', provider: 'github', scopes: []}];
  try {
    return fn();
  } finally {
    vault.ready = originalReady;
    vault.listCredentials = originalList;
  }
}

function mockRecord(payload = {}, rid = 'mock') {
  return {
    get(name) { return name === 'payload' ? payload : undefined; },
    getString(name) { return name === 'rid' ? rid : ''; },
    set() {},
  };
}

function mockEvent() {
  const app = {
    findRecordsByFilter() { return []; },
    findFirstRecordByFilter() { return null; },
    findRecordById() { return null; },
    findCollectionByNameOrId() { return {}; },
    save() {},
    delete() {},
  };
  return {
    app,
    auth: {id: 'audit-auth'},
    request: {header: {get() { return ''; }}},
  };
}

function ownerContext() {
  return {
    ownerId: 'audit-owner',
    employeeId: 'audit-owner',
    isOwner: true,
    modules: [
      'tasks', 'treasury', 'finance', 'organizations', 'contacts', 'calendar',
      'knowledge', 'crm', 'roadmap', 'audio', 'horizon', 'presentation',
      'media', 'connectors', 'github', 'ai',
    ],
  };
}

function validateSchema(schema, where) {
  assert.ok(schema && typeof schema === 'object' && !Array.isArray(schema), `${where}: parameters must be an object`);
  assert.equal(schema.type, 'object', `${where}: top-level parameters.type must be object`);
  assert.ok(schema.properties && typeof schema.properties === 'object' && !Array.isArray(schema.properties), `${where}: parameters.properties must be an object`);
  if (schema.required != null) {
    assert.ok(Array.isArray(schema.required), `${where}: required must be an array`);
    for (const key of schema.required) {
      assert.equal(typeof key, 'string', `${where}: required entries must be strings`);
      assert.ok(Object.prototype.hasOwnProperty.call(schema.properties, key), `${where}: required key ${key} is missing from properties`);
    }
  }
  for (const [key, property] of Object.entries(schema.properties)) {
    assert.ok(property && typeof property === 'object' && !Array.isArray(property), `${where}.${key}: property schema must be an object`);
    const type = property.type;
    const validType = typeof type === 'string' || (Array.isArray(type) && type.length > 0 && type.every((item) => typeof item === 'string'));
    assert.ok(validType, `${where}.${key}: property type is missing/invalid`);
    if (property.enum != null) {
      assert.ok(Array.isArray(property.enum) && property.enum.length > 0, `${where}.${key}: enum must be a non-empty array`);
    }
  }
}

function inventory(options = {}) {
  const githubConnected = options.githubConnected !== false;
  const e = mockEvent();
  const ctx = ownerContext();
  const files = adapterFiles();
  assert.ok(files.length > 0, 'No Wesi AI adapters registered');
  assert.equal(new Set(files).size, files.length, 'Duplicate adapter module in wesi_ai_tools.js');

  const raw = [];
  for (const file of files) {
    const adapter = require(path.join(HOOKS, file));
    assert.equal(typeof adapter.definitions, 'function', `${file}: missing definitions()`);
    assert.equal(typeof adapter.execute, 'function', `${file}: missing execute()`);
    const defs = file === 'wesi_ai_github_connector.js' && githubConnected
      ? withConnectedGithub(() => adapter.definitions(e, ctx))
      : adapter.definitions(e, ctx);
    assert.ok(Array.isArray(defs), `${file}: definitions() must return an array`);
    for (const def of defs) raw.push({file, adapter, def});
    if (typeof adapter.context === 'function') {
      const runContext = () => adapter.context(e, ctx, '');
      if (file === 'wesi_ai_github_connector.js' && githubConnected) {
        assert.doesNotThrow(() => withConnectedGithub(runContext), `${file}: context() throws for connected owner smoke context`);
      } else {
        assert.doesNotThrow(runContext, `${file}: context() throws for owner smoke context`);
      }
    }
  }
  return {e, ctx, files, raw};
}

function assertStructuredResult(result, name) {
  assert.ok(result && typeof result === 'object' && !Array.isArray(result), `${name}: executor must return structured object`);
  assert.equal(typeof result.ok, 'boolean', `${name}: executor result must contain boolean ok`);
  if (result.ok !== true) {
    assert.equal(typeof result.code, 'string', `${name}: failed executor result must contain code`);
    assert.equal(typeof result.message, 'string', `${name}: failed executor result must contain message`);
  }
}

auditTest('all adapter definitions are registered, unique and schema-valid', () => {
  const {raw} = inventory({githubConnected: true});
  const seen = new Map();
  for (const {file, def} of raw) {
    assert.ok(def && typeof def === 'object' && !Array.isArray(def), `${file}: invalid tool definition`);
    assert.equal(typeof def.name, 'string', `${file}: tool name must be a string`);
    assert.ok(def.name.trim(), `${file}: empty tool name`);
    assert.equal(def.name, def.name.trim(), `${file}: tool name contains outer whitespace`);
    assert.match(def.name, /^[a-z][a-z0-9_]{1,119}$/, `${file}: unsupported tool name ${def.name}`);
    assert.equal(typeof def.description, 'string', `${def.name}: description must be a string`);
    assert.ok(def.description.trim().length >= 8, `${def.name}: description is too short`);
    validateSchema(def.parameters, def.name);
    assert.ok(!seen.has(def.name), `Duplicate tool ${def.name} in ${seen.get(def.name)} and ${file}`);
    seen.set(def.name, file);
    assert.ok(registry.get(def.name), `${def.name}: adapter definition has no capability registry entry`);
  }

  const registered = registry.registeredNames().slice().sort();
  const defined = [...seen.keys()].sort();
  assert.deepEqual(registered, defined, 'Capability registry and adapter definitions are out of sync');
});

auditTest('central registry does not silently drop any connected owner-visible tool', () => {
  const {e, ctx, raw} = inventory({githubConnected: true});
  const central = withConnectedGithub(() => require(toolsPath).definitions(e, ctx));
  assert.ok(Array.isArray(central));
  const names = central.map((item) => item.name).sort();
  const rawNames = raw.map((item) => item.def.name).sort();
  assert.deepEqual(names, rawNames, 'wesi_ai_tools.definitions() dropped or duplicated a tool');
  for (const item of central) {
    assert.ok(item.wesiCapability, `${item.name}: missing decorated wesiCapability`);
  }
});

auditTest('GitHub tools are hidden cleanly when no GitHub credential is connected', () => {
  const {raw} = inventory({githubConnected: false});
  assert.equal(raw.some(({def}) => String(def.name || '').startsWith('github_')), false);
});

auditTest('risk metadata and confirmation rules are coherent for every tool', () => {
  for (const name of registry.registeredNames()) {
    const cap = registry.get(name);
    assert.ok(cap, `${name}: missing capability`);
    assert.ok(['READ', 'WRITE', 'DESTRUCTIVE'].includes(cap.risk), `${name}: unknown risk ${cap.risk}`);
    assert.ok(cap.module, `${name}: missing module`);
    assert.ok(cap.action, `${name}: missing action`);
    assert.ok(cap.entityType, `${name}: missing entityType`);

    const initial = riskPolicy.evaluate(cap, {});
    if (cap.risk === 'DESTRUCTIVE') {
      assert.equal(cap.confirmationRequired, true, `${name}: destructive tool must require confirmation`);
      assert.equal(initial.allowed, false, `${name}: destructive tool must not run before confirmation`);
      assert.equal(initial.code, 'CONFIRMATION_REQUIRED', `${name}: destructive tool must request confirmation`);
      const confirmed = riskPolicy.evaluate(cap, {confirmedByTicket: true});
      assert.equal(confirmed.allowed, true, `${name}: confirmed destructive tool must be allowed by risk policy`);
    } else {
      assert.equal(cap.confirmationRequired, false, `${name}: non-destructive tool unexpectedly requires confirmation`);
      assert.equal(initial.allowed, true, `${name}: READ/WRITE tool unexpectedly denied by risk policy`);
    }
  }
});

auditTest('every read-only tool has a non-throwing executor smoke path', () => {
  const {e, ctx, raw} = inventory({githubConnected: true});
  for (const {file, adapter, def} of raw) {
    const cap = registry.get(def.name);
    if (!cap || cap.risk !== 'READ') continue;
    let result;
    assert.doesNotThrow(() => {
      result = adapter.execute(e, ctx, def.name, {}, '', {audit: true});
    }, `${file}/${def.name}: read executor throws on empty-data smoke invocation`);
    assertStructuredResult(result, def.name);
  }
});

auditTest('every mutating tool has a non-throwing invalid-input validation path', () => {
  const {e, ctx, raw} = inventory({githubConnected: true});
  for (const {file, adapter, def} of raw) {
    const cap = registry.get(def.name);
    if (!cap || cap.risk === 'READ') continue;
    let result;
    assert.doesNotThrow(() => {
      result = adapter.execute(e, ctx, def.name, {}, '', {audit: true});
    }, `${file}/${def.name}: mutating executor throws instead of rejecting empty input safely`);
    assertStructuredResult(result, def.name);
  }
});

auditTest('central context aggregation remains safe with empty data', () => {
  const e = mockEvent();
  const ctx = ownerContext();
  const central = require(toolsPath);
  let result;
  assert.doesNotThrow(() => { result = withConnectedGithub(() => central.context(e, ctx, '')); });
  assert.ok(result && typeof result === 'object' && !Array.isArray(result));
  assert.ok(Object.prototype.hasOwnProperty.call(result, 'activeOrganizationId'));
});

auditTest('test harness record remains PocketBase-like', () => {
  const row = mockRecord({id: 'x'}, 'rid-x');
  assert.deepEqual(row.get('payload'), {id: 'x'});
  assert.equal(row.getString('rid'), 'rid-x');
});
