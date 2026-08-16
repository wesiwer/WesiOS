import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
globalThis.__hooks = here;

class Row {
  constructor(payload, rid) {
    this.values = { payload, rid };
  }
  get(name) { return this.values[name]; }
  getString(name) { return String(this.values[name] ?? ''); }
}

const calls = [];
const organizations = [
  new Row({ id: 'org_wesi_inc', name: 'Wesi Inc', baseCurrency: 'RUB' }, 'o1'),
  new Row({ id: 'org_real', name: 'Real Org', baseCurrency: 'RUB' }, 'o2'),
];
const transactions = [
  new Row({ id: 't1', organizationId: 'org_real', title: 'Sale', amount: 2500, type: 'income', date: '2026-08-10T12:00:00Z', category: 'Sales' }, 't1'),
  new Row({ id: 't2', organizationId: 'org_real', title: 'Hosting', amount: 400, type: 'expense', date: '2026-08-11T12:00:00Z', category: 'Infra' }, 't2'),
  new Row({ id: 't3', organizationId: 'org_wesi_inc', title: 'Other org', amount: 9999, type: 'income', date: '2026-08-12T12:00:00Z' }, 't3'),
];

const e = {
  app: {
    findRecordsByFilter(_collection, filter, _sort, maxRecords, _offset, params) {
      calls.push(maxRecords);
      assert.ok(maxRecords > 0, 'maxRecords must stay positive');
      if (filter.includes("coll='organizations'")) return organizations;
      if (filter.includes("coll='organization_grants'")) return [];
      if (params?.coll === 'transactions') return transactions;
      return [];
    },
  },
};
const ctx = { isOwner: true, ownerId: 'owner', employeeId: 'owner', modules: [] };
const tools = require('./wesi_ai_finance_tools.js');
const result = tools.execute(
  e,
  ctx,
  'finance_summary',
  { from: '2026-08-01', to: '2026-08-31' },
  'org_real',
);

assert.equal(result.ok, true);
assert.equal(result.result.organizationId, 'org_real');
assert.equal(result.result.transactionCount, 2);
assert.equal(result.result.income, 2500);
assert.equal(result.result.expense, 400);
assert.equal(result.result.net, 2100);
assert.ok(calls.every((value) => value > 0));
console.log('Wesi AI finance nonzero regression: OK');
