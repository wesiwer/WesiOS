export const PERSONA_COAGENT_PROTOCOL = 'wesi.persona-coagent.v1';
export const MAX_COAGENT_CONTEXT_ITEMS = 8;
export const MAX_COAGENT_CONTEXT_CHARS = 12000;
export const MAX_COAGENT_REVIEW_ROUNDS = 1;
export const MAX_COAGENT_TOOL_TURNS = 2;

const SAFE_CONTEXT_KINDS = new Set([
  'user_request',
  'conversation_excerpt',
  'verified_tool_result',
  'memory_excerpt',
  'project_context',
  'attachment_summary',
]);

const FORBIDDEN_CONTEXT_KINDS = new Set([
  'chain_of_thought',
  'hidden_reasoning',
  'system_prompt',
  'provider_prompt',
  'credential',
  'secret',
  'raw_service_envelope',
]);

const FORBIDDEN_AGENT_CAPABILITIES = new Set([
  'agent.spawn',
  'agent.delegate',
  'agent.create',
  'subagent.spawn',
  'subagent.create',
  'persona.handoff',
]);

const FORBIDDEN_RESULT_KEYS = new Set([
  'analysis',
  'reasoning',
  'chainOfThought',
  'chain_of_thought',
  'hiddenReasoning',
  'hidden_reasoning',
  'systemPrompt',
  'system_prompt',
]);

function clampInt(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(number)));
}

function cleanText(value, maxChars) {
  const text = String(value || '').replace(/\u0000/g, '').trim();
  return text.length <= maxChars ? text : text.slice(0, maxChars);
}

function cleanPersona(value) {
  return cleanText(value, 80).replace(/[\r\n\t]/g, ' ');
}

function cleanCapability(value) {
  const capability = String(value || '').trim();
  return /^[a-zA-Z0-9_.:-]{1,120}$/.test(capability) ? capability : '';
}

function uniqueCapabilities(values) {
  const result = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const capability = cleanCapability(raw);
    if (!capability || seen.has(capability)) continue;
    seen.add(capability);
    result.push(capability);
  }
  return result;
}

export function scopeCoagentContext(items, options = {}) {
  const maxItems = clampInt(options.maxItems, 1, MAX_COAGENT_CONTEXT_ITEMS, MAX_COAGENT_CONTEXT_ITEMS);
  const maxChars = clampInt(options.maxChars, 256, MAX_COAGENT_CONTEXT_CHARS, MAX_COAGENT_CONTEXT_CHARS);
  const result = [];
  let usedChars = 0;

  for (const raw of Array.isArray(items) ? items : []) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
    const kind = cleanText(raw.kind, 80).toLowerCase();
    if (!SAFE_CONTEXT_KINDS.has(kind) || FORBIDDEN_CONTEXT_KINDS.has(kind)) continue;
    const text = cleanText(raw.text, maxChars);
    if (!text) continue;
    const remaining = maxChars - usedChars;
    if (remaining <= 0 || result.length >= maxItems) break;
    const scopedText = text.slice(0, remaining);
    result.push({
      kind,
      label: cleanText(raw.label, 160),
      text: scopedText,
      verified: raw.verified === true,
    });
    usedChars += scopedText.length;
  }
  return result;
}

export function scopeCoagentCapabilities({requested, granted, allowlisted, sideEffectCapabilities = []} = {}) {
  const requestedSet = new Set(uniqueCapabilities(requested));
  const grantedSet = new Set(uniqueCapabilities(granted));
  const allowlistedSet = new Set(uniqueCapabilities(allowlisted));
  const sideEffects = new Set(uniqueCapabilities(sideEffectCapabilities));
  const result = [];

  for (const capability of requestedSet) {
    if (!grantedSet.has(capability) || !allowlistedSet.has(capability)) continue;
    if (FORBIDDEN_AGENT_CAPABILITIES.has(capability)) continue;
    if (sideEffects.has(capability)) continue;
    result.push(capability);
  }
  return result;
}

export function createPersonaHandoff(input = {}) {
  const leadPersona = cleanPersona(input.leadPersona);
  const coagentPersona = cleanPersona(input.coagentPersona);
  const parentRequestId = cleanText(input.parentRequestId, 160);
  const task = cleanText(input.task, 4000);
  if (!parentRequestId) throw new Error('WAI_COAGENT_REQUEST_ID_REQUIRED');
  if (!leadPersona || !coagentPersona || leadPersona.toLowerCase() === coagentPersona.toLowerCase()) {
    throw new Error('WAI_COAGENT_PERSONA_INVALID');
  }
  if (!task) throw new Error('WAI_COAGENT_TASK_REQUIRED');
  if (Number(input.depth || 1) !== 1) throw new Error('WAI_COAGENT_RECURSION_FORBIDDEN');

  const capabilities = scopeCoagentCapabilities({
    requested: input.requestedCapabilities,
    granted: input.grantedCapabilities,
    allowlisted: input.allowlistedCapabilities,
    sideEffectCapabilities: input.sideEffectCapabilities,
  });
  const context = scopeCoagentContext(input.context, input.contextLimits);
  const reviewRounds = clampInt(input.maxReviewRounds, 0, MAX_COAGENT_REVIEW_ROUNDS, MAX_COAGENT_REVIEW_ROUNDS);
  const toolTurns = clampInt(input.maxToolTurns, 0, MAX_COAGENT_TOOL_TURNS, MAX_COAGENT_TOOL_TURNS);

  const handoff = {
    protocol: PERSONA_COAGENT_PROTOCOL,
    kind: 'persona_handoff',
    handoffId: cleanText(input.handoffId, 160) || `${parentRequestId}:coagent`,
    parentRequestId,
    depth: 1,
    leadPersona,
    coagentPersona,
    task,
    context,
    capabilities,
    limits: {
      maxReviewRounds: reviewRounds,
      maxToolTurns: toolTurns,
      maxContextItems: MAX_COAGENT_CONTEXT_ITEMS,
      maxContextChars: MAX_COAGENT_CONTEXT_CHARS,
    },
    policy: {
      finalOwner: 'lead',
      canSpawnAgents: false,
      canDelegate: false,
      canPerformDestructiveActions: false,
      exposeChainOfThought: false,
    },
    outputSchema: {
      summary: 'string',
      findings: 'string[]',
      risks: 'string[]',
      recommendation: 'string',
      artifacts: 'string[]',
    },
  };
  validatePersonaHandoff(handoff);
  return handoff;
}

export function validatePersonaHandoff(handoff) {
  if (!handoff || typeof handoff !== 'object' || Array.isArray(handoff)) throw new Error('WAI_COAGENT_HANDOFF_INVALID');
  if (handoff.protocol !== PERSONA_COAGENT_PROTOCOL || handoff.kind !== 'persona_handoff') throw new Error('WAI_COAGENT_PROTOCOL_INVALID');
  if (Number(handoff.depth) !== 1) throw new Error('WAI_COAGENT_RECURSION_FORBIDDEN');
  if (!cleanText(handoff.parentRequestId, 160) || !cleanText(handoff.task, 4000)) throw new Error('WAI_COAGENT_HANDOFF_INVALID');
  const lead = cleanPersona(handoff.leadPersona);
  const coagent = cleanPersona(handoff.coagentPersona);
  if (!lead || !coagent || lead.toLowerCase() === coagent.toLowerCase()) throw new Error('WAI_COAGENT_PERSONA_INVALID');
  if (handoff.policy?.finalOwner !== 'lead' || handoff.policy?.canSpawnAgents !== false || handoff.policy?.canDelegate !== false || handoff.policy?.canPerformDestructiveActions !== false || handoff.policy?.exposeChainOfThought !== false) {
    throw new Error('WAI_COAGENT_POLICY_INVALID');
  }
  if (Number(handoff.limits?.maxReviewRounds) > MAX_COAGENT_REVIEW_ROUNDS || Number(handoff.limits?.maxToolTurns) > MAX_COAGENT_TOOL_TURNS) {
    throw new Error('WAI_COAGENT_BUDGET_INVALID');
  }
  for (const capability of uniqueCapabilities(handoff.capabilities)) {
    if (FORBIDDEN_AGENT_CAPABILITIES.has(capability)) throw new Error('WAI_COAGENT_RECURSION_FORBIDDEN');
  }
  for (const item of Array.isArray(handoff.context) ? handoff.context : []) {
    const kind = cleanText(item?.kind, 80).toLowerCase();
    if (!SAFE_CONTEXT_KINDS.has(kind) || FORBIDDEN_CONTEXT_KINDS.has(kind)) throw new Error('WAI_COAGENT_CONTEXT_INVALID');
    if (kind === 'verified_tool_result' && item?.verified !== true) throw new Error('WAI_COAGENT_CONTEXT_UNVERIFIED');
  }
  return true;
}

function assertNoHiddenFields(value, depth = 0) {
  if (depth > 5 || value == null) return;
  if (Array.isArray(value)) {
    for (const item of value) assertNoHiddenFields(item, depth + 1);
    return;
  }
  if (typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_RESULT_KEYS.has(key)) throw new Error('WAI_COAGENT_HIDDEN_REASONING_FORBIDDEN');
    assertNoHiddenFields(child, depth + 1);
  }
}

function cleanStringList(value, maxItems = 12, maxChars = 1200) {
  const result = [];
  for (const item of Array.isArray(value) ? value : []) {
    const text = cleanText(item, maxChars);
    if (text) result.push(text);
    if (result.length >= maxItems) break;
  }
  return result;
}

export function validatePersonaCoagentResult(raw, handoff) {
  validatePersonaHandoff(handoff);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('WAI_COAGENT_RESULT_INVALID');
  assertNoHiddenFields(raw);
  const summary = cleanText(raw.summary, 6000);
  if (!summary) throw new Error('WAI_COAGENT_RESULT_INVALID');
  return {
    protocol: PERSONA_COAGENT_PROTOCOL,
    handoffId: handoff.handoffId,
    persona: handoff.coagentPersona,
    summary,
    findings: cleanStringList(raw.findings),
    risks: cleanStringList(raw.risks),
    recommendation: cleanText(raw.recommendation, 3000),
    artifacts: cleanStringList(raw.artifacts, 20, 500),
    reviewRound: clampInt(raw.reviewRound, 0, handoff.limits.maxReviewRounds, 0),
    finalOwner: 'lead',
  };
}

export function validateLeadReview(raw, handoff) {
  validatePersonaHandoff(handoff);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('WAI_COAGENT_REVIEW_INVALID');
  assertNoHiddenFields(raw);
  const decision = cleanText(raw.decision, 24).toLowerCase();
  if (decision !== 'accept' && decision !== 'revise') throw new Error('WAI_COAGENT_REVIEW_INVALID');
  const revisionRequest = cleanText(raw.revisionRequest, 2000);
  if (decision === 'revise' && !revisionRequest) throw new Error('WAI_COAGENT_REVIEW_INVALID');
  return {
    protocol: PERSONA_COAGENT_PROTOCOL,
    handoffId: handoff.handoffId,
    reviewer: handoff.leadPersona,
    decision,
    revisionRequest: decision === 'revise' ? revisionRequest : '',
    reviewRound: decision === 'revise' ? 1 : 0,
  };
}

export function buildCoagentEvent(handoff, phase, detail = {}) {
  validatePersonaHandoff(handoff);
  const allowedPhases = new Set(['handoff', 'start', 'review', 'revision', 'result', 'fallback']);
  if (!allowedPhases.has(phase)) throw new Error('WAI_COAGENT_EVENT_INVALID');
  return {
    type: 'agent',
    phase,
    role: 'coagent',
    name: handoff.coagentPersona,
    lead: handoff.leadPersona,
    handoffId: handoff.handoffId,
    label: cleanText(detail.label, 180),
    detail: cleanText(detail.detail, 500),
  };
}
