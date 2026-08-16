function rows(e, ctx, collection) {
  try {
    return e.app.findRecordsByFilter(
      "wesios_records", "owner={:owner} && coll={:coll} && deleted=false",
      "-stamp", 0, 0, {owner: ctx.ownerId, coll: collection},
    );
  } catch (_) { return []; }
}

function day(value, fallback) {
  const raw = String(value || "").trim();
  if (!raw) return fallback;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  return Number.isFinite(Date.parse(raw + "T00:00:00Z")) ? raw : null;
}

function round(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function leaders(map) {
  return Object.keys(map)
    .map((category) => ({category: category, amount: round(map[category])}))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 8);
}

function transactionFromRow(row, policy, organizationId) {
  const p = policy.payload(row);
  if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) return null;
  const timestamp = Date.parse(String(p.date || ""));
  const amount = Number(p.amount);
  if (!Number.isFinite(timestamp) || !Number.isFinite(amount) || amount < 0) return null;
  return {
    id: String(p.id || row.getString("rid") || ""),
    title: String(p.title || ""),
    amount: round(amount),
    type: String(p.type || "expense"),
    date: new Date(timestamp).toISOString(),
    timestamp: timestamp,
    accountId: p.accountId == null ? null : String(p.accountId),
    category: p.category == null ? null : String(p.category),
    recurring: p.isRecurring === true,
    anomaly: p.isAnomaly === true,
  };
}

function accountState(e, ctx, policy, organizationId, transactions, nowMs) {
  const source = rows(e, ctx, "accounts");
  const accounts = [];
  for (const row of source) {
    const p = policy.payload(row);
    if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
    if (p.archived === true) continue;
    const openingBalance = Number(p.openingBalance || 0);
    if (!Number.isFinite(openingBalance)) continue;
    accounts.push({
      id: String(p.id || row.getString("rid") || ""),
      name: String(p.name || ""),
      openingBalance: round(openingBalance),
      balance: openingBalance,
    });
  }

  const byId = {};
  for (const account of accounts) byId[account.id] = account;
  let unassignedBalance = 0;
  for (const tx of transactions) {
    if (tx.timestamp > nowMs || tx.recurring) continue;
    const signed = tx.type === "income" ? tx.amount : -tx.amount;
    const account = tx.accountId ? byId[tx.accountId] : null;
    if (account) account.balance += signed;
    else unassignedBalance += signed;
  }

  let currentBalance = unassignedBalance;
  let openingBalance = 0;
  for (const account of accounts) {
    openingBalance += account.openingBalance;
    currentBalance += account.balance;
    account.balance = round(account.balance);
  }
  return {
    openingBalance: round(openingBalance),
    currentBalance: round(currentBalance),
    accountCount: accounts.length,
    accounts: accounts.map((account) => ({id: account.id, name: account.name, balance: account.balance})),
  };
}

module.exports = {
  definitions: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return [];
    return [
      {
        name: "finance_summary",
        description: "Получить реальные финансы организации из WesiOS: currentBalance — сколько денег сейчас на активных счетах; income/expense/net — фактический поток за выбранный период. Для вопросов «сколько сейчас денег» используй currentBalance, а не net.",
        parameters: {type: "object", properties: {organizationId: {type: "string"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}}},
      },
      {
        name: "finance_transactions",
        description: "Получить ограниченный список реальных разрешённых финансовых операций WesiOS за период.",
        parameters: {type: "object", properties: {organizationId: {type: "string"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}, type: {type: "string", enum: ["income", "expense"]}, limit: {type: "integer", minimum: 1, maximum: 50}}},
      },
    ];
  },

  context: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return {financeOrganizations: []};
    const state = policy.access(e, ctx);
    const allowed = Object.keys(state.financeOrgIds)
      .filter((id) => state.financeOrgIds[id] === true && state.orgs[id])
      .map((id) => ({id: id, name: state.orgs[id].name, baseCurrency: state.orgs[id].baseCurrency}));
    return {financeOrganizations: allowed};
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к финансовым модулям"};
    const input = args && typeof args === "object" ? args : {};
    const state = policy.access(e, ctx);
    const requested = String(input.organizationId || activeOrganizationId || "").trim();
    const organizationId = policy.select(state, requested);
    if (!organizationId) return {ok: false, code: "FORBIDDEN", message: "Нет права просматривать финансы этой организации"};

    const now = new Date();
    const nowMs = now.getTime();
    const defaultTo = now.toISOString().slice(0, 10);
    const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, now.getUTCDate()));
    const defaultFrom = start.toISOString().slice(0, 10);
    const from = day(input.from, defaultFrom);
    const to = day(input.to, defaultTo);
    if (!from || !to || from > to) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный период"};
    const fromMs = Date.parse(from + "T00:00:00Z");
    const toMs = Date.parse(to + "T23:59:59.999Z");

    const allTransactions = [];
    for (const row of rows(e, ctx, "transactions")) {
      const tx = transactionFromRow(row, policy, organizationId);
      if (tx) allTransactions.push(tx);
    }
    const filtered = allTransactions.filter((tx) => tx.timestamp >= fromMs && tx.timestamp <= toMs);

    if (name === "finance_transactions") {
      const type = String(input.type || "");
      const limit = Math.max(1, Math.min(50, Number(input.limit || 20)));
      const selected = filtered.filter((tx) => !type || tx.type === type).slice(0, limit)
        .map(({timestamp, ...tx}) => tx);
      return {ok: true, result: {organizationId: organizationId, from: from, to: to, transactions: selected}};
    }

    if (name === "finance_summary") {
      let income = 0, expense = 0, recurringExpense = 0, anomalyCount = 0;
      const expenseCategories = {}, incomeCategories = {};
      for (const tx of filtered) {
        const category = tx.category || "Без категории";
        if (tx.recurring) {
          if (tx.type === "expense") recurringExpense += tx.amount;
          if (tx.anomaly) anomalyCount++;
          continue;
        }
        if (tx.type === "income") {
          income += tx.amount;
          incomeCategories[category] = (incomeCategories[category] || 0) + tx.amount;
        } else {
          expense += tx.amount;
          expenseCategories[category] = (expenseCategories[category] || 0) + tx.amount;
        }
        if (tx.anomaly) anomalyCount++;
      }
      const balances = accountState(e, ctx, policy, organizationId, allTransactions, nowMs);
      return {ok: true, result: {
        organizationId: organizationId,
        organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId,
        reportingCurrency: state.orgs[organizationId] ? state.orgs[organizationId].baseCurrency : "RUB",
        asOf: now.toISOString(),
        currentBalance: balances.currentBalance,
        openingBalance: balances.openingBalance,
        accountCount: balances.accountCount,
        accounts: balances.accounts,
        from: from,
        to: to,
        transactionCount: filtered.filter((tx) => !tx.recurring).length,
        income: round(income),
        expense: round(expense),
        net: round(income - expense),
        recurringExpense: round(recurringExpense),
        anomalyCount: anomalyCount,
        topExpenseCategories: leaders(expenseCategories),
        topIncomeCategories: leaders(incomeCategories),
      }};
    }

    return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный финансовый инструмент"};
  },
};