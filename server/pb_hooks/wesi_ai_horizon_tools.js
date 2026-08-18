function rows(e, ctx, coll) {
  return e.app.findRecordsByFilter(
    "wesios_records",
    "owner={:owner} && coll={:coll} && deleted=false",
    "-stamp",
    5000,
    0,
    {owner: ctx.ownerId, coll: coll},
  );
}

function round(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function date(value) {
  const parsed = new Date(String(value || ""));
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

module.exports = {
  definitions: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) return [];
    return [{
      name: "horizon_snapshot",
      description: "Прочитать на основном сервере Wesi разрешённый ledger snapshot АКТИВНОЙ организации для Horizon. Для вопросов о текущем остатке используй currentBalance. Если WesiOS передал activeOrganizationId, не подменяй его аргументом модели. Ошибка чтения данных возвращается как ошибка, а не как нулевой баланс.",
      parameters: {
        type: "object",
        properties: {organizationId: {type: "string", description: "Используй только если WesiOS не передал активную организацию"}},
      },
    }];
  },

  context: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) return {horizonOrganizations: []};
    try {
      const state = policy.access(e, ctx);
      return {
        horizonOrganizations: Object.keys(state.forecastOrgIds)
          .filter((id) => state.forecastOrgIds[id] === true && state.orgs[id])
          .map((id) => ({id: id, name: state.orgs[id].name, baseCurrency: state.orgs[id].baseCurrency})),
        horizonOrganizationRule: "activeOrganizationId from WesiOS is authoritative; never invent or switch organization IDs",
      };
    } catch (_) {
      return {horizonOrganizations: [], horizonContextUnavailable: true};
    }
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    if (name !== "horizon_snapshot") {
      return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Horizon-инструмент"};
    }
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) {
      return {ok: false, code: "FORBIDDEN", message: "Нет доступа к модулю Horizon"};
    }
    const input = args && typeof args === "object" ? args : {};
    let state;
    try {
      state = policy.access(e, ctx);
    } catch (_) {
      return {
        ok: false,
        code: "HORIZON_DATA_UNAVAILABLE",
        message: "Не удалось прочитать организационный контекст Horizon. Нулевые данные не подставлены.",
      };
    }
    const organizationId = policy.select(
      state,
      String(activeOrganizationId || input.organizationId || ""),
    );
    if (!organizationId) {
      return {ok: false, code: "FORBIDDEN", message: "Для Horizon нужны view_forecast и view_finance этой организации"};
    }

    let accounts;
    let transactions;
    try {
      accounts = rows(e, ctx, "accounts");
      transactions = rows(e, ctx, "transactions");
    } catch (_) {
      return {
        ok: false,
        code: "HORIZON_DATA_UNAVAILABLE",
        message: "Не удалось прочитать финансовый ledger WesiOS. Нулевой баланс не подставлен.",
      };
    }
    if (!Array.isArray(accounts) || !Array.isArray(transactions)) {
      return {ok: false, code: "HORIZON_DATA_UNAVAILABLE", message: "Ledger WesiOS вернул некорректный набор данных"};
    }

    let balance = 0;
    let income = 0;
    let expense = 0;
    let count = 0;
    const now = new Date();
    const historyStart = new Date(now.getTime() - 90 * 86400000);

    for (const row of accounts) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId || p.archived === true) continue;
      const opening = Number(p.openingBalance || 0);
      if (Number.isFinite(opening)) balance += opening;
    }

    // Keep this exactly aligned with AccountService.summaries(): recurring
    // templates do not affect actual balance, future operations do not count,
    // and legacy materialized recurring-income rows are excluded to prevent a
    // historical double count. Actual Treasury balance is in reporting amount
    // (`amount`), not organizationBaseAmount.
    const recurringIncomeIds = [];
    for (const row of transactions) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      if (p.isRecurring === true && String(p.type || "expense") === "income") {
        recurringIncomeIds.push(String(p.id || row.getString("rid") || ""));
      }
    }
    const legacyAutoIncome = (p, row) => {
      if (p.isRecurring === true || String(p.type || "expense") !== "income") return false;
      const id = String(p.id || row.getString("rid") || "");
      return recurringIncomeIds.some((recurringId) => recurringId && id.indexOf(recurringId + "_") === 0);
    };

    for (const row of transactions) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      if (p.isRecurring === true || legacyAutoIncome(p, row)) continue;
      const amount = Number(p.amount);
      const at = date(p.date);
      if (!Number.isFinite(amount) || amount < 0 || !at || at > now) continue;
      const signed = String(p.type || "expense") === "income" ? amount : -amount;
      balance += signed;
      if (at >= historyStart) {
        count++;
        if (signed >= 0) income += amount;
        else expense += amount;
      }
    }

    const spendPerDay = expense / 90;
    return {ok: true, result: {
      engine: "Wesi Horizon",
      engineScope: "server-ledger",
      fullClientMonteCarlo: false,
      organizationId: organizationId,
      organizationName: state.orgs[organizationId].name,
      reportingCurrency: state.orgs[organizationId].baseCurrency,
      asOf: now.toISOString(),
      currentBalance: round(balance),
      sourceAccountCount: accounts.length,
      sourceTransactionCount: transactions.length,
      recent90Days: {
        transactionCount: count,
        income: round(income),
        expense: round(expense),
        net: round(income - expense),
        spendPerDay: round(spendPerDay),
      },
      cushionDays: spendPerDay > 0 ? Math.max(0, Math.floor(balance / spendPerDay)) : null,
      caveat: "Full client Horizon Monte-Carlo/calibration/business-context is not reproduced by this server snapshot.",
    }};
  },
};
