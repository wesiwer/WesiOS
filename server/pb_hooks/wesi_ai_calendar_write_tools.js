function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function recordById(e, ctx, id) {
  try {
    return e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='calendar_events' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: id},
    );
  } catch (_) { return null; }
}

function parseStart(value) {
  const date = new Date(String(value || ""));
  if (!Number.isFinite(date.getTime())) return null;
  const now = Date.now();
  if (date.getTime() < now - 20 * 365 * 86400000 || date.getTime() > now + 20 * 365 * 86400000) return null;
  return date.toISOString();
}

function normalizeRepeat(value) {
  const repeat = String(value || "none");
  return ["none", "daily", "weekly", "monthly", "yearly"].indexOf(repeat) >= 0 ? repeat : null;
}

function normalizeReminder(value) {
  if (value == null || value === "") return {ok: true, value: null};
  const n = Number(value);
  if (!Number.isFinite(n) || Math.floor(n) !== n || n < 0 || n > 525600) return {ok: false};
  return {ok: true, value: n};
}

function applyFields(target, input, creating) {
  if (creating || Object.prototype.hasOwnProperty.call(input, "title")) {
    const title = String(input.title || "").trim();
    if (!title || title.length > 500) return {ok: false, message: "Некорректное название события"};
    target.title = title;
  }
  if (creating || Object.prototype.hasOwnProperty.call(input, "startAt")) {
    const startAt = parseStart(input.startAt);
    if (!startAt) return {ok: false, message: "Некорректная дата/время события"};
    target.startAt = startAt;
  }
  if (Object.prototype.hasOwnProperty.call(input, "notes")) target.notes = String(input.notes || "").slice(0, 10000);
  if (Object.prototype.hasOwnProperty.call(input, "durationMinutes")) {
    const duration = Number(input.durationMinutes);
    if (!Number.isFinite(duration) || Math.floor(duration) !== duration || duration < 1 || duration > 10080) return {ok: false, message: "Некорректная длительность события"};
    target.durationMinutes = duration;
  } else if (creating) target.durationMinutes = 60;
  if (Object.prototype.hasOwnProperty.call(input, "allDay")) target.allDay = input.allDay === true;
  else if (creating) target.allDay = false;
  if (Object.prototype.hasOwnProperty.call(input, "repeat")) {
    const repeat = normalizeRepeat(input.repeat);
    if (!repeat) return {ok: false, message: "Некорректный повтор события"};
    target.repeat = repeat;
  } else if (creating) target.repeat = "none";
  if (Object.prototype.hasOwnProperty.call(input, "reminderMinutesBefore")) {
    const reminder = normalizeReminder(input.reminderMinutesBefore);
    if (!reminder.ok) return {ok: false, message: "Некорректное напоминание"};
    target.reminderMinutesBefore = reminder.value;
  } else if (creating) target.reminderMinutesBefore = null;
  if (Object.prototype.hasOwnProperty.call(input, "enabled")) target.enabled = input.enabled !== false;
  else if (creating) target.enabled = true;
  if (!Object.prototype.hasOwnProperty.call(target, "notes")) target.notes = "";
  return {ok: true};
}

module.exports = {
  definitions: function(e, ctx) {
    if (!ctx.isOwner && ctx.modules.indexOf("calendar") < 0) return [];
    return [
      {
        name: "calendar_create",
        description: "Создать реальное событие календаря WesiOS.",
        parameters: {type: "object", required: ["title", "startAt"], properties: {
          title: {type: "string"}, notes: {type: "string"}, startAt: {type: "string", description: "ISO date/time"},
          durationMinutes: {type: "integer", minimum: 1, maximum: 10080}, allDay: {type: "boolean"},
          repeat: {type: "string", enum: ["none", "daily", "weekly", "monthly", "yearly"]},
          reminderMinutesBefore: {type: ["integer", "null"], minimum: 0, maximum: 525600}, enabled: {type: "boolean"}
        }},
      },
      {
        name: "calendar_update",
        description: "Изменить реальное событие календаря WesiOS. Меняй только явно указанные поля.",
        parameters: {type: "object", required: ["eventId"], properties: {
          eventId: {type: "string"}, title: {type: "string"}, notes: {type: "string"}, startAt: {type: "string"},
          durationMinutes: {type: "integer", minimum: 1, maximum: 10080}, allDay: {type: "boolean"},
          repeat: {type: "string", enum: ["none", "daily", "weekly", "monthly", "yearly"]},
          reminderMinutesBefore: {type: ["integer", "null"]}, enabled: {type: "boolean"}
        }},
      },
      {
        name: "calendar_delete",
        description: "Удалить событие календаря WesiOS. DESTRUCTIVE: требуется отдельное подтверждение пользователя.",
        parameters: {type: "object", required: ["eventId"], properties: {eventId: {type: "string"}}},
      },
    ];
  },

  context: function() { return {}; },

  execute: function(e, ctx, name, args) {
    if (!ctx.isOwner && ctx.modules.indexOf("calendar") < 0) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к календарю"};
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    const now = new Date().toISOString();

    if (name === "calendar_create") {
      const id = "wai_calendar_" + Date.now() + "_" + $security.randomString(8);
      const value = {id: id};
      const applied = applyFields(value, input, true);
      if (!applied.ok) return {ok: false, code: "VALIDATION_ERROR", message: applied.message};
      const collection = e.app.findCollectionByNameOrId("wesios_records");
      const record = new Record(collection);
      record.set("owner", ctx.ownerId); record.set("org", "wesi-inc"); record.set("coll", "calendar_events");
      record.set("rid", id); record.set("payload", value); record.set("stamp", now); record.set("deleted", false);
      e.app.save(record);
      return {ok: true, result: {event: value}};
    }

    const id = String(input.eventId || "").trim();
    if (!id || id.length > 180) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный eventId"};
    const record = recordById(e, ctx, id);
    if (!record) return {ok: false, code: "NOT_FOUND", message: "Событие не найдено"};
    if (name === "calendar_delete") {
      record.set("deleted", true); record.set("stamp", now); e.app.save(record);
      return {ok: true, result: {event: {id: id, deleted: true}}};
    }
    if (name !== "calendar_update") return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Calendar-инструмент"};
    const before = payloadOf(record);
    const value = {};
    for (const key of Object.keys(before)) value[key] = before[key];
    value.id = String(before.id || id);
    const applied = applyFields(value, input, false);
    if (!applied.ok) return {ok: false, code: "VALIDATION_ERROR", message: applied.message};
    record.set("payload", value); record.set("stamp", now); record.set("deleted", false); e.app.save(record);
    return {ok: true, result: {event: value}};
  },
};
