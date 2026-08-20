export const DYNAMIC_SUBAGENT_PROTOCOL = 'wesi.dynamic-subagent.v1';
export const MAX_DYNAMIC_SUBAGENTS = 3;
export const MAX_SUBAGENT_CONTEXT_ITEMS = 10;
export const MAX_SUBAGENT_CONTEXT_CHARS = 16000;
export const MAX_SUBAGENT_TOOL_TURNS = 3;
export const MAX_SUBAGENT_OUTPUT_CHARS = 9000;
export const MAX_SUBAGENT_WORKSPACE_EDITS = 8;

const SAFE_CONTEXT_KINDS = new Set([
  'user_request',
  'conversation_excerpt',
  'verified_tool_result',
  'memory_excerpt',
  'project_context',
  'attachment_summary',
  'workspace_snapshot',
  'lead_instruction',
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

const FORBIDDEN_CAPABILITIES = new Set([
  'agent.spawn',
  'agent.delegate',
  'agent.create',
  'subagent.spawn',
  'subagent.create',
  'persona.handoff',
  'connector.secret.read',
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
  'credential',
  'secret',
]);

// Structured result exists only while the request is executing. Keeping it in
// a WeakMap lets the visible result event reuse the already validated public
// fields without mutating the subagent spec or leaking hidden provider data.
const VISIBLE_RESULT_BY_SPEC = new WeakMap();

function clampInt(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(number)));
}

function cleanText(value, maxChars) {
  const text = String(value || '').replace(/\u0000/g, '').trim();
  return text.length <= maxChars ? text : text.slice(0, maxChars);
}

function cleanId(value, maxChars = 160) {
  return cleanText(value, maxChars).replace(/[^a-zA-Z0-9_.:-]/g, '_');
}

function cleanRole(value) {
  return cleanText(value, 120).replace(/[\r\n\t]/g, ' ');
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

function cleanPath(value) {
  const path = String(value || '').replace(/\\/g, '/').replace(/^\/+/, '').trim();
  if (!path || path.includes('\u0000') || path.split('/').some((part) => part === '..')) return '';
  return path.slice(0, 500);
}

function cleanPathList(values, maxItems = 32) {
  const result = [];
  const seen = new Set();
  for (const raw of Array.isArray(values) ? values : []) {
    const path = cleanPath(raw);
    if (!path || seen.has(path)) continue;
    seen.add(path);
    result.push(path);
    if (result.length >= maxItems) break;
  }
  return result;
}

export function scopeDynamicContext(items, options = {}) {
  const maxItems = clampInt(options.maxItems, 1, MAX_SUBAGENT_CONTEXT_ITEMS, MAX_SUBAGENT_CONTEXT_ITEMS);
  const maxChars = clampInt(options.maxChars, 256, MAX_SUBAGENT_CONTEXT_CHARS, MAX_SUBAGENT_CONTEXT_CHARS);
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
    result.push({kind, label: cleanText(raw.label, 160), text: scopedText, verified: raw.verified === true});
    usedChars += scopedText.length;
  }
  return result;
}

export function scopeDynamicCapabilities({requested, granted, allowlisted, destructiveCapabilities = []} = {}) {
  const requestedSet = new Set(uniqueCapabilities(requested));
  const grantedSet = new Set(uniqueCapabilities(granted));
  const allowlistedSet = new Set(uniqueCapabilities(allowlisted));
  const destructiveSet = new Set(uniqueCapabilities(destructiveCapabilities));
  const result = [];
  for (const capability of requestedSet) {
    if (!grantedSet.has(capability) || !allowlistedSet.has(capability)) continue;
    if (FORBIDDEN_CAPABILITIES.has(capability) || destructiveSet.has(capability)) continue;
    result.push(capability);
  }
  return result;
}

export function createDynamicSubagentSpec(input = {}) {
  const parentRequestId = cleanId(input.parentRequestId);
  const role = cleanRole(input.role);
  const task = cleanText(input.task, 5000);
  if (!parentRequestId) throw new Error('WAI_SUBAGENT_REQUEST_ID_REQUIRED');
  if (!role) throw new Error('WAI_SUBAGENT_ROLE_REQUIRED');
  if (!task) throw new Error('WAI_SUBAGENT_TASK_REQUIRED');
  if (Number(input.depth || 1) !== 1) throw new Error('WAI_SUBAGENT_RECURSION_FORBIDDEN');

  const capabilities = scopeDynamicCapabilities({
    requested: input.requestedCapabilities,
    granted: input.grantedCapabilities,
    allowlisted: input.allowlistedCapabilities,
    destructiveCapabilities: input.destructiveCapabilities,
  });
  const readablePaths = cleanPathList(input.readablePaths);
  const writablePaths = cleanPathList(input.writablePaths);
  const writableSet = new Set(writablePaths);
  const workspaceReads = readablePaths.filter((path) => !writableSet.has(path));

  const spec = {
    protocol: DYNAMIC_SUBAGENT_PROTOCOL,
    kind: 'dynamic_subagent',
    agentId: cleanId(input.agentId) || `${parentRequestId}:subagent:${cleanId(role, 60)}`,
    parentRequestId,
    depth: 1,
    role,
    task,
    context: scopeDynamicContext(input.context, input.contextLimits),
    capabilities,
    workspace: {
      workspaceId: cleanId(input.workspaceId) || `${parentRequestId}:workspace`,
      baseRevision: Math.max(0, clampInt(input.baseRevision, 0, 1000000000, 0)),
      readablePaths: [...workspaceReads, ...writablePaths].slice(0, 32),
      writablePaths,
    },
    limits: {
      maxToolTurns: clampInt(input.maxToolTurns, 0, MAX_SUBAGENT_TOOL_TURNS, 1),
      maxOutputChars: clampInt(input.maxOutputChars, 1000, MAX_SUBAGENT_OUTPUT_CHARS, MAX_SUBAGENT_OUTPUT_CHARS),
      maxWorkspaceEdits: clampInt(input.maxWorkspaceEdits, 0, MAX_SUBAGENT_WORKSPACE_EDITS, 4),
      deadlineMs: clampInt(input.deadlineMs, 1000, 120000, 45000),
    },
    policy: {
      finalOwner: 'lead',
      canSpawnAgents: false,
      canDelegate: false,
      canPerformDestructiveActions: false,
      exposeChainOfThought: false,
      workspaceWritesRequireRevisionMatch: true,
    },
  };
  validateDynamicSubagentSpec(spec);
  return spec;
}

export function validateDynamicSubagentSpec(spec) {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) throw new Error('WAI_SUBAGENT_SPEC_INVALID');
  if (spec.protocol !== DYNAMIC_SUBAGENT_PROTOCOL || spec.kind !== 'dynamic_subagent') throw new Error('WAI_SUBAGENT_PROTOCOL_INVALID');
  if (Number(spec.depth) !== 1) throw new Error('WAI_SUBAGENT_RECURSION_FORBIDDEN');
  if (!cleanId(spec.parentRequestId) || !cleanId(spec.agentId) || !cleanRole(spec.role) || !cleanText(spec.task, 5000)) throw new Error('WAI_SUBAGENT_SPEC_INVALID');
  if (spec.policy?.finalOwner !== 'lead' || spec.policy?.canSpawnAgents !== false || spec.policy?.canDelegate !== false || spec.policy?.canPerformDestructiveActions !== false || spec.policy?.exposeChainOfThought !== false || spec.policy?.workspaceWritesRequireRevisionMatch !== true) {
    throw new Error('WAI_SUBAGENT_POLICY_INVALID');
  }
  if (Number(spec.limits?.maxToolTurns) > MAX_SUBAGENT_TOOL_TURNS || Number(spec.limits?.maxOutputChars) > MAX_SUBAGENT_OUTPUT_CHARS || Number(spec.limits?.maxWorkspaceEdits) > MAX_SUBAGENT_WORKSPACE_EDITS) {
    throw new Error('WAI_SUBAGENT_BUDGET_INVALID');
  }
  for (const capability of uniqueCapabilities(spec.capabilities)) {
    if (FORBIDDEN_CAPABILITIES.has(capability)) throw new Error('WAI_SUBAGENT_RECURSION_FORBIDDEN');
  }
  for (const item of Array.isArray(spec.context) ? spec.context : []) {
    const kind = cleanText(item?.kind, 80).toLowerCase();
    if (!SAFE_CONTEXT_KINDS.has(kind) || FORBIDDEN_CONTEXT_KINDS.has(kind)) throw new Error('WAI_SUBAGENT_CONTEXT_INVALID');
    if (kind === 'verified_tool_result' && item?.verified !== true) throw new Error('WAI_SUBAGENT_CONTEXT_UNVERIFIED');
  }
  return true;
}

function assertNoHiddenFields(value, depth = 0) {
  if (depth > 6 || value == null) return;
  if (Array.isArray(value)) {
    for (const item of value) assertNoHiddenFields(item, depth + 1);
    return;
  }
  if (typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_RESULT_KEYS.has(key)) throw new Error('WAI_SUBAGENT_HIDDEN_REASONING_FORBIDDEN');
    assertNoHiddenFields(child, depth + 1);
  }
}

function cleanStringList(value, maxItems = 16, maxChars = 1600) {
  const result = [];
  for (const item of Array.isArray(value) ? value : []) {
    const text = cleanText(item, maxChars);
    if (text) result.push(text);
    if (result.length >= maxItems) break;
  }
  return result;
}

function cleanWorkspaceEdits(value, spec) {
  const allowed = new Set(cleanPathList(spec.workspace?.writablePaths));
  const edits = [];
  for (const raw of Array.isArray(value) ? value : []) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
    const path = cleanPath(raw.path);
    if (!path || !allowed.has(path)) continue;
    const operation = String(raw.operation || 'replace').trim().toLowerCase();
    if (operation !== 'replace' && operation !== 'create') continue;
    const content = cleanText(raw.content, 120000);
    const baseRevision = Math.max(0, clampInt(raw.baseRevision, 0, 1000000000, spec.workspace?.baseRevision || 0));
    edits.push({path, operation, content, baseRevision});
    if (edits.length >= spec.limits.maxWorkspaceEdits) break;
  }
  return edits;
}

function structuredVisibleResult(result) {
  if (!result) return '';
  const lines = [];
  if (result.summary) lines.push(`Краткий вывод: ${result.summary}`);
  if (Array.isArray(result.findings) && result.findings.length) {
    lines.push('', 'Наблюдения:');
    for (const item of result.findings) lines.push(`• ${item}`);
  }
  if (Array.isArray(result.risks) && result.risks.length) {
    lines.push('', 'Риски:');
    for (const item of result.risks) lines.push(`• ${item}`);
  }
  if (result.recommendation) lines.push('', `Рекомендация: ${result.recommendation}`);
  return cleanText(lines.join('\n'), MAX_SUBAGENT_OUTPUT_CHARS);
}

export function validateDynamicSubagentResult(raw, spec) {
  validateDynamicSubagentSpec(spec);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('WAI_SUBAGENT_RESULT_INVALID');
  assertNoHiddenFields(raw);
  const summary = cleanText(raw.summary, spec.limits.maxOutputChars);
  if (!summary) throw new Error('WAI_SUBAGENT_RESULT_INVALID');
  const result = {
    protocol: DYNAMIC_SUBAGENT_PROTOCOL,
    agentId: spec.agentId,
    role: spec.role,
    summary,
    findings: cleanStringList(raw.findings),
    risks: cleanStringList(raw.risks),
    recommendation: cleanText(raw.recommendation, 4000),
    workspaceEdits: cleanWorkspaceEdits(raw.workspaceEdits, spec),
    finalOwner: 'lead',
  };
  VISIBLE_RESULT_BY_SPEC.set(spec, result);
  return result;
}

export function buildDynamicSubagentEvent(spec, phase, detail = {}) {
  validateDynamicSubagentSpec(spec);
  const allowedPhases = new Set(['planned', 'start', 'tool', 'workspace', 'result', 'conflict', 'fallback']);
  if (!allowedPhases.has(phase)) throw new Error('WAI_SUBAGENT_EVENT_INVALID');
  // «(субагент)» подписывает каждую строку централизованно, а не в шести
  // местах вызова. Co-Agent (Зейн ↔ Нирвана) даёт похожие по форме подписи
  // («Нирвана: проверка», «Передано Нирвана»), и без явной метки человек не
  // может на глаз отличить временного специалиста от второй персоны.
  const label = cleanText(detail.label, 160);
  const isResult = phase === 'result';
  const files = cleanPathList(detail.files, 40);
  const validatedResult = isResult ? VISIBLE_RESULT_BY_SPEC.get(spec) : null;
  const resultDetail = structuredVisibleResult(validatedResult);
  return {
    type: 'agent',
    phase,
    role: 'subagent',
    name: spec.role,
    agentId: spec.agentId,
    parentRequestId: spec.parentRequestId,
    label: label ? `${label} (субагент)` : label,
    // На первом уровне результат всё равно показывается кратко (UI ограничит
    // строки), но второй уровень получает полный уже валидированный публичный
    // результат специалиста: summary, findings, risks и recommendation.
    detail: resultDetail || cleanText(detail.detail, isResult ? MAX_SUBAGENT_OUTPUT_CHARS : 1200),
    // Поручение едет вместе с событием. Оно пригодится и для глубокого уровня,
    // поэтому не режем его до старых 400 символов.
    task: cleanText(spec.task, 5000),
    ...(Number(detail.additions) > 0 ? {additions: Number(detail.additions)} : {}),
    ...(Number(detail.deletions) > 0 ? {deletions: Number(detail.deletions)} : {}),
    ...(files.length ? {files} : {}),
  };
}
