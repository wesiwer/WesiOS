import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const hooks = path.resolve(here, '../pb_hooks');

function read(name) {
  return fs.readFileSync(path.join(hooks, name), 'utf8');
}

function adapterFiles() {
  const source = read('wesi_ai_tools.js');
  const files = [];
  const re = /require\(base \+ ["'](wesi_ai_[a-z0-9_]+\.js)["']\)/g;
  for (const match of source.matchAll(re)) files.push(match[1]);
  return files;
}

function literalToolNames(source) {
  const out = [];
  const re = /\bname\s*:\s*["']([a-z][a-z0-9_]{2,100})["']/g;
  for (const match of source.matchAll(re)) out.push(match[1]);
  return out;
}

function registry() {
  const source = read('wesi_ai_capability_registry.js');
  const out = new Map();
  const re = /^\s*([a-z][a-z0-9_]+):\s*\{module:\s*["'][^"']+["'],\s*action:\s*["'][^"']+["'],\s*risk:\s*(RISK_READ|RISK_WRITE|RISK_DESTRUCTIVE),/gm;
  for (const match of source.matchAll(re)) {
    const risk = match[2].replace('RISK_', '');
    out.set(match[1], risk);
  }
  return out;
}

function connectorPolicy() {
  const source = read('wesi_ai_connector_policy.js');
  const out = new Map();
  const re = /^\s*(github_[a-z0-9_]+):\s*\{risk:\s*(READ|WRITE|DESTRUCTIVE),/gm;
  for (const match of source.matchAll(re)) out.set(match[1], match[2]);
  return out;
}

test('Wesi AI tool adapters and Capability Registry stay in exact sync', () => {
  const files = adapterFiles();
  assert.ok(files.length >= 10, 'expected the central tool router to list the production adapters');
  assert.equal(new Set(files).size, files.length, 'adapter list contains duplicates');

  const owners = new Map();
  for (const file of files) {
    const source = read(file);
    const names = [...new Set(literalToolNames(source))];
    assert.ok(names.length > 0, `${file} exposes no literal tool definitions`);
    for (const name of names) {
      const previous = owners.get(name);
      assert.equal(previous, undefined, `tool ${name} is exposed by both ${previous} and ${file}`);
      owners.set(name, file);
    }
  }

  const registered = registry();
  assert.ok(registered.size >= 20, 'Capability Registry unexpectedly empty');

  const exposedNames = [...owners.keys()].sort();
  const registeredNames = [...registered.keys()].sort();
  assert.deepEqual(
    exposedNames,
    registeredNames,
    'every adapter definition must be registered, and every registered capability must be exposed by exactly one adapter',
  );
});

test('GitHub connector policy risk classes match the central Capability Registry', () => {
  const registered = registry();
  const connector = connectorPolicy();
  const githubSource = read('wesi_ai_github_connector.js');
  const githubDefinitions = new Set(literalToolNames(githubSource).filter((name) => name.startsWith('github_')));

  assert.ok(connector.size >= 10, 'GitHub connector policy unexpectedly empty');
  assert.deepEqual(
    [...githubDefinitions].sort(),
    [...connector.keys()].sort(),
    'GitHub connector definitions and connector policy must expose the same tools',
  );

  for (const [name, risk] of connector) {
    assert.equal(registered.get(name), risk, `${name} has different risk in connector policy and central registry`);
  }
});

test('destructive capabilities remain confirmation-gated by the central registry', () => {
  const registered = registry();
  const expected = new Set([
    'tasks_archive',
    'finance_transaction_delete',
    'calendar_delete',
    'knowledge_archive',
    'crm_client_archive',
    'crm_deal_archive',
    'roadmap_archive',
    'github_branch_delete',
    'github_pull_request_merge',
    'github_workflow_dispatch',
  ]);
  const actual = new Set(
    [...registered.entries()].filter(([, risk]) => risk === 'DESTRUCTIVE').map(([name]) => name),
  );
  assert.deepEqual([...actual].sort(), [...expected].sort());
});
