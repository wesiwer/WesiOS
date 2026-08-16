export const PERSONA_COAGENT_PROTOCOL = 'wesi.persona.coagent.v1';
export const MAX_COAGENT_CONTEXT_ITEMS = 12;
export const MAX_COAGENT_CONTEXT_CHARS = 12000;
export const MAX_COAGENT_CAPABILITIES = 24;
export const MAX_COAGENT_REVIEW_ROUNDS = 1;

const ALLOWED_PERSONAS = new Set(['zane', 'nirvana']);
const ALLOWED_CONTEXT_KINDS = new Set([
  'user_request',
  'conversation_excerpt',
  'project_fact',
  'verified_tool_result',
  'attachment_summary',
]);

function cleanText(value, maxChars) {
  const text = String(value || '').replace(/\u0000/g, '').trim();
  return text.length <= maxChars ? text : text.slice(0, maxChars);
}

export function normalizePersona(value) {
  const persona = String(value || '').trim().toLowerCase();
  return ALLOWED_PERSONAS.has(persona) ? persona : null;
}

export function counterpartPersona(value) {
  const persona = normalizePersona(value);
  if (persona === 'zane') return 'nirvana';
  if (persona === 'nirvana') return 'zane';
  return null;
}

function normalizeCapability(value) {
  const capability = String(value || '').trim();
  if (!capability || capability.length > 120) return null;
  if (!/^[a-zA-Z0-9._:-]+$/.test(capability)) return null;
  return capability;
}

export function intersectCapabilities(requested, available) {
  const availableSet = new Set(
    (Array.isArray(available) ? available : [])
      .map(normalizeCapability)
      .filter(Boolean),
  );
  const result = [];
  const seen = new Set();
  for (const item of Array.isArray(requested) ? requested : []) {
    const capability = normalizeCapability(item);
    if (!capability || seen.has(capability) || !availableSet.has(capability)) continue;
    seen.add(capability);
    result.push(capability);
    if (result.length >= MAX_COAGENT_CAPABILITIES) break;
  }
  return result;
}

export function scopeCoAgentContext(items) {
  const scoped = [];
  let totalChars = 0;
  for (const raw of Array.isArray(items) ? items : []) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
    const kind = String(raw.kind || '').trim();
    if (!ALLOWED_CONTEXT_KINDS.has(kind)) continue;
    const content = cleanText(raw.content, 3000);
    if (!content) continue;
    const remaining = MAX_COAGENT_CONTEXT_CHARS - totalChars;
    if (remaining <= 0) break;
    const bounded = content.slice(0, remaining);
    const item = {kind, content: bounded};
    const label = cleanText(raw.label, 160);
    const source = cleanText(raw.source, 240);
    if (label) item.label = label;
    if (source) item.source = source;
    scoped.push(item);
    totalChars += bounded.length;
    if (scoped.length >= MAX_COAGENT_CONTEXT_ITEMS) break;
  }
  return scoped;
}

export function createPersonaCoAgentHandoff({
  leadPersona,
  objective,
  context = [],
  requestedCapabilities = [],
  availableCapabilities = [],
  reviewRound = 0,
} = {}) {
  const lead = normalizePersona(leadPersona);
  const coAgent = counterpartPersona(lead);
  const boundedObjective = cleanText(objective, 4000);
  const round = Number(reviewRound);
  if (!lead || !coAgent || !boundedObjective) {
    const error = new Error('WAI_COAGENT_HANDOFF_INVALID');
    error.status = 400;
    throw error;
  }
  if (!Number.isInteger(round) || round < 0 || round > MAX_COAGENT_REVIEW_ROUNDS) {
    const error = new Error('WAI_COAGENT_REVIEW_LIMIT');
    error.status = 400;
    throw error;
  }
  return {
    protocol: PERSONA_COAGENT_PROTOCOL,
    lead,
    coAgent,
    objective: boundedObjective,
    context: scopeCoAgentContext(context),
    capabilities: intersectCapabilities(requestedCapabilities, availableCapabilities),
    reviewRound: round,
    constraints: {
      canDelegate: false,
      mayWriteFinal: false,
      verifiedToolResultsOnly: true,
      maxReviewRounds: MAX_COAGENT_REVIEW_ROUNDS,
    },
  };
}

export function validatePersonaCoAgentHandoff(value, {availableCapabilities = []} = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  if (value.protocol !== PERSONA_COAGENT_PROTOCOL) return false;
  const lead = normalizePersona(value.lead);
  const coAgent = normalizePersona(value.coAgent);
  if (!lead || !coAgent || lead === coAgent || counterpartPersona(lead) !== coAgent) return false;
  if (!cleanText(value.objective, 4000)) return false;
  if (!Number.isInteger(value.reviewRound) || value.reviewRound < 0 || value.reviewRound > MAX_COAGENT_REVIEW_ROUNDS) return false;
  if (value.constraints?.canDelegate !== false || value.constraints?.mayWriteFinal !== false) return false;
  if (value.constraints?.verifiedToolResultsOnly !== true) return false;
  if (value.constraints?.maxReviewRounds !== MAX_COAGENT_REVIEW_ROUNDS) return false;

  const scoped = scopeCoAgentContext(value.context);
  if (!Array.isArray(value.context) || scoped.length !== value.context.length) return false;
  for (let index = 0; index < scoped.length; index += 1) {
    const actual = value.context[index];
    const expected = scoped[index];
    if (actual.kind !== expected.kind || actual.content !== expected.content) return false;
    if ((actual.label || '') !== (expected.label || '')) return false;
    if ((actual.source || '') !== (expected.source || '')) return false;
  }

  const capabilities = Array.isArray(value.capabilities) ? value.capabilities : null;
  if (!capabilities || capabilities.length > MAX_COAGENT_CAPABILITIES) return false;
  const allowed = new Set(
    (Array.isArray(availableCapabilities) ? availableCapabilities : [])
      .map(normalizeCapability)
      .filter(Boolean),
  );
  const seen = new Set();
  for (const raw of capabilities) {
    const capability = normalizeCapability(raw);
    if (!capability || seen.has(capability) || !allowed.has(capability)) return false;
    seen.add(capability);
  }
  return true;
}

export function buildPersonaCoAgentSystemPrompt(handoff) {
  if (!validatePersonaCoAgentHandoff(handoff, {availableCapabilities: handoff?.capabilities || []})) {
    const error = new Error('WAI_COAGENT_HANDOFF_INVALID');
    error.status = 400;
    throw error;
  }
  return [
    '[WESI_PERSONA_COAGENT_HANDOFF]',
    JSON.stringify(handoff),
    '',
    'Ты Co-Agent, а не Lead. Решай только переданную подзадачу.',
    'Не создавай других агентов и не делегируй работу дальше.',
    'Используй только перечисленные capabilities и только переданный scoped context.',
    'Не считай неподтверждённые данные verified tool results.',
    'Не пиши финальный ответ пользователю: верни Lead краткий результат, риски, факты и рекомендации для интеграции.',
  ].join('\n');
}
