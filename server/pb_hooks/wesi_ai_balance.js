// Единственное место, где WesiOS считает остаток на счетах для Wesi AI.
//
// Расчёт повторяет экран «Казна» (account_service.dart): начальный остаток
// счёта плюс его доходы минус расходы. Отдельно от него живших копий быть не
// должно: два инструмента, называющих разные суммы «текущим остатком», хуже
// одного, который отказывается отвечать.
//
// Четыре исключения оригинала обязательны:
//   1. повторяющиеся операции — шаблоны, а не деньги;
//   2. порождённые ими старые автодоходы с id "<шаблон>_<дата>" — иначе доход
//      учтётся дважды;
//   3. операции с датой в будущем;
//   4. архивные счета и операции на них.
const MAIN_ACCOUNT = "main";
const ROOT_ORG = "org_wesi_inc";

function round(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function mainAccountIdFor(organizationId) {
  return organizationId === ROOT_ORG ? MAIN_ACCOUNT : MAIN_ACCOUNT + ":" + organizationId;
}

/**
 * @param accountRows строки коллекции accounts
 * @param transactionRows строки коллекции transactions
 * @param payload функция извлечения payload из строки
 * @param organizationId организация, по которой считаем
 */
function compute(accountRows, transactionRows, payload, organizationId) {
  if (!Array.isArray(accountRows) || !Array.isArray(transactionRows)) return null;

  const accounts = [];
  for (const row of accountRows) {
    const p = payload(row);
    if (String(p.organizationId || ROOT_ORG) !== organizationId) continue;
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

  const recurringIncomeIds = [];
  for (const row of transactionRows) {
    const p = payload(row);
    if (p.isRecurring !== true || String(p.type || "expense") !== "income") continue;
    const id = String(p.id || row.getString("rid") || "");
    if (id) recurringIncomeIds.push(id);
  }

  const nowMs = Date.now();
  for (const row of transactionRows) {
    const p = payload(row);
    const orgId = String(p.organizationId || ROOT_ORG);
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

module.exports = {MAIN_ACCOUNT, ROOT_ORG, round, mainAccountIdFor, compute};
