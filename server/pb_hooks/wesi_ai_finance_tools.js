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

// Остаток на счетах считается ровно тем же правилом, что показывает экран
// «Казна» (lib/features/treasury/services/account_service.dart): начальный
// остаток счёта плюс его доходы минус расходы.
//
// Если правило разойдётся хоть в одной детали, Wesi AI будет называть сумму,
// которой пользователь не видит нигде в приложении, — а это хуже отказа
// отвечать. Поэтому здесь повторены все четыре исключения оригинала.
const MAIN_ACCOUNT = "main";

function mainAccountIdFor(organizationId) {
  return organizationId === "org_wesi_inc" ? MAIN_ACCOUNT : MAIN_ACCOUNT + ":" + organizationId;
}

function balanceState(e, ctx, policy, organizationId) {
  let accountRows = [];
  try {
    accountRows = rows(e, ctx, "accounts");
  } catch (_) {
    return null;
  }
  if (!Array.isArray(accountRows)) return null;

  let transactionRows = [];
  try {
    transactionRows = rows(e, ctx, "transactions");
  } catch (_) {
    return null;
  }
  if (!Array.isArray(transactionRows)) return null;

  const accounts = [];
  for (const row of accountRows) {
    const p = policy.payload(row);
    if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
    if (p.archived === true) continue;
    const id = String(p.id || row.getString("rid") || "");
    if (!id) continue;
    const opening = Number(p.openingBalance || 0);
    accounts.push({
      id: id,
      name: String(p.name || id),
      opening: Number.isFinite(opening) ? opening : 0,
      income: 0,
      expense: 0,
    });
  }
  if (!accounts.length) return {accounts: [], currentBalance: 0};

  const byId = {};
  for (const account of accounts) byId[account.id] = account;

  // Повторяющиеся доходы — шаблоны, а не деньги. Старые сборки порождали из
  // них настоящие операции с id вида "<шаблон>_<дата>"; такие тоже нельзя
  // складывать, иначе один и тот же доход учтётся дважды.
  const recurringIncomeIds = [];
  for (const row of transactionRows) {
    const p = policy.payload(row);
    if (p.isRecurring !== true || String(p.type || "expense") !== "income") continue;
    const id = String(p.id || row.getString("rid") || "");
    if (id) recurringIncomeIds.push(id);
  }

  const nowMs = Date.now();
  for (const row of transactionRows) {
    const p = policy.payload(row);
    const orgId = String(p.organizationId || policy.ROOT_ORG);
    if (orgId !== organizationId) continue;
    if (p.isRecurring === true) continue;

    const id = String(p.id || row.getString("rid") || "");
    const type = String(p.type || "expense");
    if (type === "income" && recurringIncomeIds.some((parent) => id.indexOf(parent + "_") === 0)) continue;

    const amount = Number(p.amount);
    const timestamp = Date.parse(String(p.date || ""));
    if (!Number.isFinite(amount) || amount < 0 || !Number.isFinite(timestamp) || timestamp > nowMs) continue;

    const accountId = p.accountId == null || String(p.accountId) === "" ? mainAccountIdFor(orgId) : String(p.accountId);
    const account = byId[accountId];
    if (!account) continue;
    if (type === "income") account.income += amount;
    else account.expense += amount;
  }

  let total = 0;
  const result = [];
  for (const account of accounts) {
    const balance = account.opening + account.income - account.expense;
    total += balance;
    result.push({id: account.id, name: account.name, balance: round(balance)});
  }
  return {accounts: result, currentBalance: round(total)};
}

module.exports = {
  definitions: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_finance_policy.js`);
    if (!policy.hasModule(ctx)) return [];
    return [
      {
        name: "finance_summary",
        description: "Посчитать на основном сервере Wesi финансы АКТИВНОЙ организации: текущий остаток на счетах (currentBalance и разбивка accounts) и сводку за период. На вопрос «сколько денег на счету / сколько у меня есть» отвечай currentBalance, а не net за период. Если WesiOS передал activeOrganizationId, не подменяй его другой организацией и не выдумывай ID.",
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
      const balance = balanceState(e, ctx, policy, organizationId);
      if (!balance) {
        return {
          ok: false,
          code: "FINANCE_DATA_UNAVAILABLE",
          message: "Не удалось прочитать счета WesiOS. Нулевой остаток не подставлен.",
        };
      }
      return {ok: true, result: {
        organizationId: organizationId,
        organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId,
        reportingCurrency: state.orgs[organizationId] ? state.orgs[organizationId].baseCurrency : "RUB",
        currentBalance: balance.currentBalance,
        accounts: balance.accounts,
        balanceRule: "currentBalance — это остаток на счетах на текущий момент, а не net за период",
        from: from, to: to, transactionCount: filtered.length,
        income: round(income), expense: round(expense), net: round(income - expense), recurringExpense: round(recurringExpense), anomalyCount: anomalyCount,
        topExpenseCategories: leaders(expenseCategories), topIncomeCategories: leaders(incomeCategories),
      }};
    }

    return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный финансовый инструмент"};
  },
};