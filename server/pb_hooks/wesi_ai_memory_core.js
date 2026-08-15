function stripFence(raw) {
  let text = String(raw || '').trim();
  if (text.startsWith('```json') && text.lastIndexOf('```') > 7) {
    text = text.slice(7, text.lastIndexOf('```')).trim();
  } else if (text.startsWith('```') && text.lastIndexOf('```') > 3) {
    text = text.slice(3, text.lastIndexOf('```')).trim();
  }
  return text;
}

function sensitive(text) {
  return /(password|парол|api[_ -]?key|token|токен|private[_ -]?key|secret|секрет|-----begin [a-z ]*private key)/i.test(String(text || ''));
}

function cleanKeywords(raw) {
  const result = [];
  for (const item of Array.isArray(raw) ? raw.slice(0, 24) : []) {
    const value = String(item || '').trim().toLowerCase();
    if (!value || value.length > 80 || result.indexOf(value) >= 0) continue;
    result.push(value);
  }
  return result;
}

function parseCompactionAnswer(answer, context) {
  let parsed;
  try {
    parsed = JSON.parse(stripFence(answer));
  } catch (_) {
    return {ok: false, code: 'WAI_MEMORY_BAD_RESPONSE'};
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return {ok: false, code: 'WAI_MEMORY_BAD_RESPONSE'};
  }
  let summary = String(parsed.summary || '').trim();
  if (!summary || summary.length > 12000) {
    return {ok: false, code: 'WAI_MEMORY_BAD_SUMMARY'};
  }
  const memories = [];
  for (const raw of Array.isArray(parsed.memories) ? parsed.memories.slice(0, 8) : []) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
    const text = String(raw.text || '').trim();
    if (!text || text.length > 4000 || sensitive(text)) continue;
    let scope = String(raw.scope || 'shared').trim().toLowerCase();
    if (['shared', 'persona', 'project', 'task'].indexOf(scope) < 0) scope = 'shared';
    const item = {
      scope: scope,
      text: text,
      keywords: cleanKeywords(raw.keywords),
      importance: Math.max(0, Math.min(Number(raw.importance || 0.5), 1)),
    };
    if (scope === 'persona') {
      if (context.persona === 'lobby') continue;
      item.persona = context.persona;
    }
    if (scope === 'project') {
      if (!context.projectId) continue;
      item.projectId = context.projectId;
    }
    if (scope === 'task') {
      if (!context.taskId) continue;
      item.taskId = context.taskId;
    }
    memories.push(item);
  }
  return {ok: true, summary: summary, memories: memories};
}

module.exports = {
  parseCompactionAnswer,
  sensitive,
};
