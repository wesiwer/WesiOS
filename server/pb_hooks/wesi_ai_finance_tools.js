function rows(e, ctx, collection) {
  // PocketBase's maxRecords argument must be positive here. A zero/invalid
  // read used to be swallowed and converted into an empty ledger, which made
  // Wesi AI confidently report 0 transactions even when synchronized rows
  // existed on Main. Never turn a backend read failure into financial zeros.
  return e.app.findRecordsByFilter(
    "wesios_records", "owner={:owner} && coll={:coll} && deleted=false",
    "-stamp", 5000, 0, {owner: ctx.ownerId, coll: collection},
  );
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

function currentBalance(e, ctx, policy, organizationId) {
  const accounts = rows(e, ctx, "accounts");
  const transactions = rows(e, ctx, "transactions");
  if (!Array.isArray(accounts) || !Array.isArray(transactions)) {
    throw new Error("invalid ledger");
  }

  let balance = 0;
  for (const row of accounts) {
    const p = policy.payload(row);
    if (String(p.organizationId || policy.ROOT_ORG) !== organizationId || p.archived === true) continue;
    const opening = Number(p.openingBalance || 0);
    if (Number.isFinite(opening)) balance += opening;
  }

  // Keep balance semantics aligned with AccountService/Horizon: recurring
  // rows are templates, future rows do not affect actual cash, and old
  // materialized recurring-income children are excluded to avoid double count.
  const recurringIncomeIds = [];
  for (const row of transactions) {
    const p = policy.payload(row);
    if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
    if (p.isRecurring === true && String(p.type || "expense") === "income") {
      recurringIncomeIds.push(String(p.id || row.getString("rid") || ""));
    }
  }
  const now = Date.now();
  for (const row of transactions) {
    const p = policy.payload(row);
    if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
    if (p.isRecurring === true) continue;
    const id = String(p.id || row.getString("rid") || "");
    if (String(p.type || "expense") === "income" && recurringIncomeIds.some((parent) => parent && id.indexOf(parent + "_") === 0)) continue;
    const amount = Number(p.amount);
    const at = Date.parse(String(p.date || ""));
    if (!Number.isFinite(amount) || amount < 0 || !Number.isFinite(at) || at > now) continue;
    balance += String(p.type || "expense") === "income" ? amount : -amount;
  }
  return round(balance);
}

module.exports = {
  definitions: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return [];
    return [
      {
        name: "finance_balance",
        description: "Получить текущий фактический баланс разрешённой АКТИВНОЙ организации WesiOS из того же ledger, что использует приложение. Не используй будущие или recurring-template операции как уже совершённые.",
        parameters: {type: "object", properties: {organizationId: {type: "string", description: "Используй только если активная организация не передана WesiOS"}}},
      },
      {
        name: "finance_summary",
        description: "Посчитать на основном сервере Wesi сводку реальных разрешённых финансов АКТИВНОЙ организации за период. Если WesiOS передал activeOrganizationId, не подменяй его другой организацией и не выдумывай ID. Возвращает transactionCount, доходы, расходы, net, категории, recurring и anomalies.",
        parameters: {type: "object", properties: {organizationId: {type: "string", description: "Используй только если активная организация не передана WesiOS"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}}},
      },
      {
        name: "finance_transactions",
        description: "Получить ограниченный список реальных разрешённых финансовых операций АКТИВНОЙ организации WesiOS за период. Если передан activeOrganizationId, не переключай организацию сам.",
        parameters: {type: "object", properties: {organizationId: {type: "string", description: "Используй только если активная организация не передана WesiOS"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}, type: {type: "string", enum: ["income", "expense"]}, limit: {type: "integer", minimum: 1, maximum: 50}}},
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
    return {
      financeOrganizations: allowed,
      financeOrganizationRule: "activeOrganizationId from WesiOS is authoritative; never invent or switch organization IDs unless the user explicitly changes organization in WesiOS",
    };
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к финансовым модулям"};
    const input = args && typeof args === "object" ? args : {};
    const state = policy.access(e, ctx);

    // The organization selected by authenticated WesiOS UI is authoritative.
    // Model-generated arguments are only a fallback when no active org exists.
    const requested = String(activeOrganizationId || input.organizationId || "").trim();
    const organizationId = policy.select(state, requested);
    if (!organizationId) return {ok: false, code: "FORBIDDEN", message: "Нет права просматривать финансы этой организации"};

    if (name === "finance_balance") {
      try {
        return {ok: true, result: {
          organizationId: organizationId,
          organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId,
          reportingCurrency: state.orgs[organizationId] ? state.orgs[organizationId].baseCurrency : "RUB",
          currentBalance: currentBalance(e, ctx, policy, organizationId),
          asOf: new Date().toISOString(),
        }};
      } catch (_) {
        return {ok: false, code: "FINANCE_DATA_UNAVAILABLE", message: "Не удалось прочитать фактический баланс WesiOS. Нулевой баланс не подставлен."};
      }
    }

    const now = new Date();
    const defaultTo = now.toISOString().slice(0, 10);
    const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, now.getUTCDate()));
    const defaultFrom = start.toISOString().slice(0, 10);
    const from = day(input.from, defaultFrom);
    const to = day(input.to, defaultTo);
    if (!from || !to || from > to) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный период"};
    const fromMs = Date.parse(from + "T00:00:00Z");
    const toMs = Date.parse(to + "T23:59:59.999Z");

    let source;
    try {
      source = rows(e, ctx, "transactions");
    } catch (_) {
      return {
        ok: false,
        code: "FINANCE_DATA_UNAVAILABLE",
        message: "Не удалось прочитать синхронизированные финансовые данные WesiOS. Нулевой результат не подставлен.",
      };
    }
    if (!Array.isArray(source)) {
      return {ok: false, code: "FINANCE_DATA_UNAVAILABLE", message: "Финансовое хранилище WesiOS вернуло некорректный набор данных"};
    }

    const filtered = [];
    for (const row of source) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      const timestamp = Date.parse(String(p.date || ""));
      const amount = Number(p.amount);
      if (!Number.isFinite(timestamp) || !Number.isFinite(amount) || amount < 0 || timestamp < fromMs || timestamp > toMs) continue;
      filtered.push({
        id: String(p.id || row.getString("rid") || ""), title: String(p.title || ""),
        amount: round(amount), type: String(p.type || "expense"), date: new Date(timestamp).toISOString(),
        category: p.category == null ? null : String(p.category), recurring: p.isRecurring === true, anomaly: p.isAnomaly === true,
      });
    }

    if (name === "finance_transactions") {
      const type = String(input.type || "");
      const limit = Math.max(1, Math.min(50, Number(input.limit || 20)));
      const selected = filtered.filter((tx) => !type || tx.type === type).slice(0, limit);
      return {ok: true, result: {organizationId: organizationId, organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId, from: from, to: to, transactionCount: filtered.length, transactions: selected}};
    }

    if (name === "finance_summary") {
      let income = 0, expense = 0, recurringExpense = 0, anomalyCount = 0;
      const expenseCategories = {}, incomeCategories = {};
      for (const tx of filtered) {
        const category = tx.category || "Без категории";
        if (tx.type === "income") {
          income += tx.amount;
          incomeCategories[category] = (incomeCategories[category] || 0) + tx.amount;
        } else {
          expense += tx.amount;
          expenseCategories[category] = (expenseCategories[category] || 0) + tx.amount;
          if (tx.recurring) recurringExpense += tx.amount;
        }
        if (tx.anomaly) anomalyCount++;
      }
      return {ok: true, result: {
        organizationId: organizationId,
        organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId,
        reportingCurrency: state.orgs[organizationId] ? state.orgs[organizationId].baseCurrency : "RUB", from: from, to: to, transactionCount: filtered.length,
        income: round(income), expense: round(expense), net: round(income - expense), recurringExpense: round(recurringExpense), anomalyCount: anomalyCount,
        topExpenseCategories: leaders(expenseCategories), topIncomeCategories: leaders(incomeCategories),
      }};
    }

    return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный финансовый инструмент"};
  },
};