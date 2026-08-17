import assert from "node:assert/strict";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");
const tool = require(path.resolve("server/pb_hooks/wesi_ai_horizon_tools.js"));

function row(rid, payload) {
  return {
    get(name) { return name === "payload" ? payload : null; },
    getString(name) { return name === "rid" ? rid : ""; },
  };
}

function appFixture({throwLedger = false} = {}) {
  const now = Date.now();
  const yesterday = new Date(now - 86400000).toISOString();
  const future = new Date(now + 86400000).toISOString();
  const org = row("org_wesi_inc", {
    id: "org_wesi_inc", name: "Wesi Inc", isRoot: true,
    parentId: null, status: "active", baseCurrency: "RUB",
  });
  const account = row("main", {
    id: "main", organizationId: "org_wesi_inc", archived: false,
    openingBalance: 1000,
  });
  const transactions = [
    row("recurring-income", {id: "recurring-income", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 5000, organizationBaseAmount: 50, isRecurring: true, date: yesterday}),
    row("recurring-income_legacy", {id: "recurring-income_legacy", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 5000, organizationBaseAmount: 50, isRecurring: false, date: yesterday}),
    row("income", {id: "income", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 200, organizationBaseAmount: 2, isRecurring: false, date: yesterday}),
    row("expense", {id: "expense", organizationId: "org_wesi_inc", accountId: "main", type: "expense", amount: 50, organizationBaseAmount: 0.5, isRecurring: false, date: yesterday}),
    row("future", {id: "future", organizationId: "org_wesi_inc", accountId: "main", type: "expense", amount: 900, organizationBaseAmount: 9, isRecurring: false, date: future}),
  ];
  return {
    findRecordsByFilter(_collection, filter, _sort, _max, _offset, params) {
      if (filter.includes("coll='organizations'")) return [org];
      if (filter.includes("coll='organization_grants'")) return [];
      if (params?.coll === "accounts") {
        if (throwLedger) throw new Error("ledger down");
        return [account];
      }
      if (params?.coll === "transactions") {
        if (throwLedger) throw new Error("ledger down");
        return transactions;
      }
      return [];
    },
  };
}

const ctx = {isOwner: true, modules: ["forecast"], ownerId: "owner", employeeId: "owner"};

test("horizon snapshot mirrors canonical Treasury actual-balance semantics", () => {
  const e = {app: appFixture()};
  const result = tool.execute(e, ctx, "horizon_snapshot", {}, "org_wesi_inc");
  assert.equal(result.ok, true);
  assert.equal(result.result.currentBalance, 1150);
  assert.equal(result.result.recent90Days.transactionCount, 2);
  assert.equal(result.result.recent90Days.income, 200);
  assert.equal(result.result.recent90Days.expense, 50);
  assert.equal(result.result.recent90Days.net, 150);
});

test("horizon does not convert a backend read failure into financial zeros", () => {
  const e = {app: appFixture({throwLedger: true})};
  const result = tool.execute(e, ctx, "horizon_snapshot", {}, "org_wesi_inc");
  assert.equal(result.ok, false);
  assert.equal(result.code, "HORIZON_DATA_UNAVAILABLE");
});
