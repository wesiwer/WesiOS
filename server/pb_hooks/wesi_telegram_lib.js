const CALLBACK_PREFIX = "w:";

function text(value) {
  return String(value == null ? "" : value).trim();
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function formatMoney(value, currency) {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return "—";
  const rounded = Math.round((amount + Number.EPSILON) * 100) / 100;
  const fixed = Number.isInteger(rounded)
    ? String(rounded)
    : rounded.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  const parts = fixed.split(".");
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const code = text(currency || "RUB").toUpperCase();
  const symbol = code === "RUB" ? "₽" : code === "USD" ? "$" : code === "EUR" ? "€" : code;
  return parts.join(",") + " " + symbol;
}

function parseCommand(raw, botUsername) {
  const input = text(raw);
  if (!input) return {name: "", args: "", raw: ""};
  if (input[0] !== "/") {
    const lower = input.toLowerCase();
    // Specific risk language must win over the generic cash stem: phrases
    // such as "кассовый разрыв" contain "касс" but are risk questions.
    if (/риск|разрыв/.test(lower)) return {name: "risk", args: "", raw: input};
    if (/касс|денег|баланс/.test(lower)) return {name: "cash", args: "", raw: input};
    if (/просроч/.test(lower)) return {name: "overdue", args: "", raw: input};
    if (/сегодня|задач/.test(lower)) return {name: "today", args: "", raw: input};
    if (/дайджест|сводк|brief/.test(lower)) return {name: "brief", args: "", raw: input};
    return {name: "unknown", args: input, raw: input};
  }
  const firstSpace = input.indexOf(" ");
  const token = (firstSpace < 0 ? input : input.slice(0, firstSpace)).slice(1);
  const args = firstSpace < 0 ? "" : input.slice(firstSpace + 1).trim();
  const at = token.indexOf("@");
  const command = (at < 0 ? token : token.slice(0, at)).toLowerCase();
  const mention = at < 0 ? "" : token.slice(at + 1).toLowerCase();
  const expected = text(botUsername).replace(/^@/, "").toLowerCase();
  if (mention && expected && mention !== expected) return {name: "foreign", args: args, raw: input};
  return {name: command, args: args, raw: input};
}

function isExplicitGroupCommand(raw, botUsername) {
  const input = text(raw);
  if (!input || input[0] !== "/") return false;
  const token = input.split(/\s+/, 1)[0].toLowerCase();
  const expected = text(botUsername).replace(/^@/, "").toLowerCase();
  return !!expected && token.endsWith("@" + expected);
}

function parseStartCode(command) {
  if (!command || command.name !== "start") return "";
  const code = text(command.args);
  return /^[A-Za-z0-9_-]{16,64}$/.test(code) ? code : "";
}

function callback(action, value) {
  const a = text(action).replace(/[^a-z0-9_-]/gi, "").slice(0, 24);
  const available = Math.max(0, 64 - CALLBACK_PREFIX.length - a.length - 1);
  const v = text(value).replace(/[^A-Za-z0-9_.:-]/g, "").slice(0, available);
  const out = CALLBACK_PREFIX + a + (v ? ":" + v : "");
  return out.length <= 64 ? out : out.slice(0, 64);
}

function parseCallback(raw) {
  const value = text(raw);
  if (value.indexOf(CALLBACK_PREFIX) !== 0 || value.length > 64) return null;
  const body = value.slice(CALLBACK_PREFIX.length);
  const split = body.indexOf(":");
  const action = split < 0 ? body : body.slice(0, split);
  const arg = split < 0 ? "" : body.slice(split + 1);
  if (!/^[a-z0-9_-]{1,24}$/i.test(action)) return null;
  if (arg && !/^[A-Za-z0-9_.:-]{1,58}$/.test(arg)) return null;
  return {action: action.toLowerCase(), value: arg};
}

function riskFromCushionDays(cushionDays) {
  if (cushionDays == null) return {level: "unknown", label: "нет расходного темпа"};
  const days = Number(cushionDays);
  if (!Number.isFinite(days) || days < 0) return {level: "unknown", label: "недостаточно данных"};
  if (days < 14) return {level: "critical", label: "критический"};
  if (days < 30) return {level: "warning", label: "повышенный"};
  return {level: "ok", label: "умеренный"};
}

function riskRank(level) {
  switch (String(level || "unknown")) {
    case "critical": return 3;
    case "warning": return 2;
    case "ok": return 1;
    default: return 0;
  }
}

function shouldNotifyRisk(previousLevel, currentLevel) {
  const current = riskRank(currentLevel);
  if (current < 2) return false;
  const previous = riskRank(previousLevel);
  return previous < 2 || current > previous;
}

function shouldNotifyOverdue(previousCount, currentCount) {
  const current = Math.max(0, Number(currentCount || 0));
  if (!Number.isFinite(current) || current <= 0) return false;
  const previous = Math.max(0, Number(previousCount || 0));
  if (!Number.isFinite(previous)) return true;
  return current > previous;
}

function dayKey(value, offsetMinutes) {
  const d = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(d.getTime())) return "";
  const offset = Math.max(-840, Math.min(840, Number(offsetMinutes || 0)));
  return new Date(d.getTime() + offset * 60000).toISOString().slice(0, 10);
}

function dueState(dueDate, now, offsetMinutes) {
  const due = new Date(String(dueDate || ""));
  const current = now instanceof Date ? now : new Date(now || Date.now());
  if (!Number.isFinite(due.getTime()) || !Number.isFinite(current.getTime())) return "none";
  const dueDay = dayKey(due, offsetMinutes);
  const nowDay = dayKey(current, offsetMinutes);
  if (dueDay < nowDay) return "overdue";
  if (dueDay === nowDay) return "today";
  return "future";
}

function localHour(nowMs, offsetMinutes) {
  const offset = Math.max(-840, Math.min(840, Number(offsetMinutes || 0)));
  const d = new Date(Number(nowMs || Date.now()) + offset * 60000);
  return d.getUTCHours();
}

function isQuietHours(nowMs, offsetMinutes, fromHour, toHour) {
  const from = Math.max(0, Math.min(23, Number(fromHour == null ? 23 : fromHour)));
  const to = Math.max(0, Math.min(23, Number(toHour == null ? 8 : toHour)));
  if (from === to) return false;
  const hour = localHour(nowMs, offsetMinutes);
  return from < to ? hour >= from && hour < to : hour >= from || hour < to;
}

function acceptRate(state, nowMs, limit, windowMs) {
  const now = Number(nowMs || Date.now());
  const max = Math.max(1, Number(limit || 20));
  const window = Math.max(1000, Number(windowMs || 60000));
  const current = state && typeof state === "object" ? state : {};
  let startedAt = Number(current.startedAt || 0);
  let count = Number(current.count || 0);
  if (!Number.isFinite(startedAt) || startedAt <= 0 || now - startedAt >= window || now < startedAt) {
    startedAt = now;
    count = 0;
  }
  if (count >= max) return {ok: false, state: {startedAt: startedAt, count: count}};
  return {ok: true, state: {startedAt: startedAt, count: count + 1}};
}

module.exports = {
  CALLBACK_PREFIX,
  escapeHtml,
  formatMoney,
  parseCommand,
  isExplicitGroupCommand,
  parseStartCode,
  callback,
  parseCallback,
  riskFromCushionDays,
  riskRank,
  shouldNotifyRisk,
  shouldNotifyOverdue,
  dueState,
  isQuietHours,
  acceptRate,
};
