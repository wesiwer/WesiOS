import {
  MAX_DYNAMIC_SUBAGENTS,
  createDynamicSubagentSpec,
  validateDynamicSubagentResult,
  buildDynamicSubagentEvent,
} from './dynamic_subagent.mjs';
import {
  createConflictSafeWorkspace,
  workspaceSnapshot,
  applySubagentWorkspaceEdits,
} from './multi_agent_workspace.mjs';
import {stepIo} from './step_io.mjs';

function stripLeadingReasoningBlocks(value) {
  let text = String(value || '').trim();
  for (let turn = 0; turn < 3; turn += 1) {
    const match = text.match(/^<(think|analysis|reasoning)>/i);
    if (!match) break;
    const closing = `</${match[1]}>`;
    const end = text.toLowerCase().indexOf(closing.toLowerCase(), match[0].length);
    if (end < 0) break;
    text = text.slice(end + closing.length).trim();
  }
  return text;
}

function stripOuterCodeFence(value) {
  const text = String(value || '').trim();
  const match = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return match ? match[1].trim() : text;
}

function parseJsonObjectText(text) {
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function extractBalancedJsonObject(value) {
  const text = String(value || '');
  for (let start = text.indexOf('{'); start >= 0; start = text.indexOf('{', start + 1)) {
    let depth = 0;
    let quoted = false;
    let escaped = false;
    for (let index = start; index < text.length; index += 1) {
      const char = text[index];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === '"') {
          quoted = false;
        }
        continue;
      }
      if (char === '"') {
        quoted = true;
        continue;
      }
      if (char === '{') depth += 1;
      if (char !== '}') continue;
      depth -= 1;
      if (depth !== 0) continue;
      const parsed = parseJsonObjectText(text.slice(start, index + 1));
      if (parsed) return parsed;
      break;
    }
  }
  return null;
}

function parseObject(value) {
  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));
  return parseJsonObjectText(text) || extractBalancedJsonObject(text);
}

function visibleSnippet(value, max = 360) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1)).trimEnd()}…`;
}

function reasoningEvent(label, detail) {
  return {type: 'activity', kind: 'reasoning', phase: 'done', label, detail};
}

const BASELINE_SUBAGENT_ROLES = Object.freeze([
  'Coding / Flutter Agent',
  'QA Agent',
  'Build Agent',
  'Research Agent',
  'Documents Agent',
  'Media Agent',
  'Review Agent',
  'Security Reviewer',
]);

function parseManualSubagentRequest(value) {
  const text = String(value || '').trim();
  const match = text.match(/^Позови\s+(?:субагента|сабагента)\s+[«"]([^»"]+)[»"]\s+и\s+поручи\s+ему\s*:\s*([\s\S]+)$/iu);
  if (!match) return null;
  const role = match[1].trim().slice(0, 120);
  const task = match[2].trim().slice(0, 5000);
  return role && task ? {role, task} : null;
}

export function parseDynamicSubagentToolRequest(value) {
  const parsed = parseObject(value);
  const tool = parsed && typeof parsed.wesiTool === 'object' && !Array.isArray(parsed.wesiTool) ? parsed.wesiTool : null;
  if (!tool) return null;
  const name = String(tool.name || '').trim();
  const args = tool.arguments && typeof tool.arguments === 'object' && !Array.isArray(tool.arguments) ? tool.arguments : {};
  return name ? {name, arguments: args} : null;
}

function plannerInput(prepared, policy) {
  const toolNames = Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames.map(String).filter(Boolean).slice(0, 40) : [];
  const maxAgents = Math.max(0, Math.min(MAX_DYNAMIC_SUBAGENTS, Number(policy.maxAgents || 0) || 0));
  return {
    system: [
      ...(Array.isArray(prepared.systemParts) ? prepared.systemParts : []),
      '[WESI_AI_DYNAMIC_SUBAGENT_PLANNER]\n' +
        `Ты Lead Coordinator. Реши, нужны ли для текущей задачи временные специалисты. Допустимо от 0 до ${maxAgents} субагентов. ` +
        'Создавай их только когда декомпозиция реально улучшает точность/проверку. Запрещены рекурсивные агенты, скрытые рассуждения, destructive actions и финальный ответ пользователю на этом шаге. ' +
        'Каждому специалисту дай узкую роль и независимую задачу. requestedCapabilities могут содержать только разрешённые read-only tools. ' +
        `Базовый каталог специалистов: ${BASELINE_SUBAGENT_ROLES.join('; ')}. Предпочитай подходящую роль из каталога, а если ни одна не подходит — создай узкую динамическую роль под задачу. ` +
        'writablePaths относятся только к изолированному coordination workspace и НЕ дают доступ к host filesystem. ' +
        'Верни ТОЛЬКО JSON без markdown: {"subagents":[{"role":"...","task":"...","requestedCapabilities":["..."],"readablePaths":["..."],"writablePaths":["..."]}]}.\n' +
        `[WESI_AI_DYNAMIC_ALLOWED_TOOLS]\n${JSON.stringify(toolNames)}`,
    ].join('\n\n'),
    history: [],
    message: String(prepared.message || '').slice(0, 16000),
    attachments: [],
  };
}

function sanitizePlan(raw, prepared, policy, workspace) {
  const parsed = parseObject(raw);
  if (!parsed || parsed.wesiTool || !Array.isArray(parsed.subagents)) throw new Error('WAI_SUBAGENT_PLAN_INVALID');
  const maxAgents = Math.max(0, Math.min(MAX_DYNAMIC_SUBAGENTS, Number(policy.maxAgents || 0) || 0));
  const result = [];
  const seenRoles = new Set();
  for (const item of parsed.subagents.slice(0, maxAgents)) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
    const role = String(item.role || '').trim().slice(0, 120);
    const roleKey = role.toLowerCase();
    if (!role || seenRoles.has(roleKey)) continue;
    seenRoles.add(roleKey);
    try {
      result.push(createDynamicSubagentSpec({
        parentRequestId: prepared.requestId,
        // The relay only accepts request identifiers containing [A-Za-z0-9_-].
        // Keep the child agent id local to the parent request instead of
        // embedding parentRequestId with colon separators. The parent request
        // already travels separately in the spec and every emitted event.
        agentId: `subagent-${result.length + 1}`,
        role,
        task: String(item.task || '').slice(0, 5000),
        context: Array.isArray(policy.context) ? policy.context : [],
        requestedCapabilities: item.requestedCapabilities,
        grantedCapabilities: policy.grantedCapabilities,
        allowlistedCapabilities: policy.allowlistedCapabilities,
        destructiveCapabilities: policy.destructiveCapabilities,
        workspaceId: workspace.workspaceId,
        baseRevision: workspace.revision,
        readablePaths: item.readablePaths,
        writablePaths: item.writablePaths,
        maxToolTurns: policy.maxToolTurns,
        maxOutputChars: policy.maxOutputChars,
        maxWorkspaceEdits: policy.maxWorkspaceEdits,
        deadlineMs: policy.deadlineMs,
      }));
    } catch {
      continue;
    }
  }
  return result;
}

function resultInstruction(spec) {
  return '[WESI_AI_DYNAMIC_SUBAGENT_OUTPUT]\n' +
    'Верни ТОЛЬКО JSON без markdown/analysis/reasoning: ' +
    '{"summary":"...","findings":["..."],"risks":["..."],"recommendation":"...","workspaceEdits":[{"path":"...","operation":"create|replace","content":"...","baseRevision":0}]}. ' +
    `workspaceEdits допускаются только для paths из writablePaths и максимум ${spec.limits.maxWorkspaceEdits}. ` +
    'Не отвечай пользователю напрямую. Не создавай других агентов.';
}

function toolInstruction(policy) {
  if (!Array.isArray(policy.toolDefinitions) || !policy.toolDefinitions.length) return '';
  return '[WESI_AI_DYNAMIC_SUBAGENT_TOOL_PROTOCOL]\n' +
    'Разрешены только явно перечисленные read-only инструменты. Для вызова верни ТОЛЬКО JSON: {"wesiTool":{"name":"tool_name","arguments":{}}}. ' +
    'Нельзя выполнять writes/deletes/merge/revoke/confirm, нельзя делегировать работу. После verified result продолжи анализ.\n' +
    JSON.stringify(policy.toolDefinitions);
}

function subagentInput(spec, policy, toolResults, workspace, finalOnly) {
  const snapshot = workspaceSnapshot(workspace, spec.workspace.readablePaths);
  const systemParts = [
    '[WESI_AI_DYNAMIC_SUBAGENT_ROLE]\n' +
      `Ты временный specialist: ${spec.role}. Выполни только переданную узкую задачу. Ты не Lead и не формируешь финальный ответ пользователю.`,
    '[WESI_AI_DYNAMIC_SUBAGENT_SPEC]\n' + JSON.stringify(spec),
    '[WESI_AI_MULTI_AGENT_WORKSPACE_SNAPSHOT]\n' + JSON.stringify(snapshot),
    resultInstruction(spec),
  ];
  const toolPart = toolInstruction(policy);
  if (toolPart && !finalOnly) systemParts.push(toolPart);
  if (toolResults.length) systemParts.push('[WESI_AI_VERIFIED_SUBAGENT_TOOL_RESULTS]\n' + JSON.stringify(toolResults));
  if (finalOnly) systemParts.push('[WESI_AI_DYNAMIC_SUBAGENT_FINAL_ONLY]\nНе вызывай инструменты. Верни structured result JSON.');
  return {system: systemParts.join('\n\n'), message: spec.task, history: [], attachments: []};
}

function safeToolResult(name, raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return {tool: name, verified: true, ok: false, code: 'SUBAGENT_TOOL_BAD_RESULT', message: 'Некорректный результат инструмента'};
  }
  return {...raw, tool: String(raw.tool || name), verified: true};
}

async function runOneSubagent({spec, policy, workspace, invokeModel, invokeTool, emit, signal, budget}) {
  const send = typeof emit === 'function' ? emit : () => {};
  send(buildDynamicSubagentEvent(spec, 'start', {
    label: `${spec.role} · за работой`,
    detail: 'Работает отдельно, с урезанными правами и своим бюджетом вызовов.',
  }));
  const toolResults = [];
  const seenCalls = new Set();
  const allowedTools = new Set(Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames.map(String) : []);
  let raw = '';

  for (let turn = 0; turn <= spec.limits.maxToolTurns; turn += 1) {
    if (signal?.aborted) throw new Error('WAI_SUBAGENT_CANCELLED');
    const finalOnly = turn >= spec.limits.maxToolTurns || budget.remainingToolTurns <= 0;
    raw = await invokeModel({
      spec,
      actor: 'subagent',
      phase: finalOnly ? 'final' : `tool-${turn + 1}`,
      input: subagentInput(spec, policy, toolResults, workspace, finalOnly),
    });
    const toolRequest = parseDynamicSubagentToolRequest(raw);
    if (!toolRequest) break;
    if (finalOnly) throw new Error('WAI_SUBAGENT_TOOL_BUDGET_EXHAUSTED');
    const signature = `${toolRequest.name}|${JSON.stringify(toolRequest.arguments)}`;
    let toolResult;
    if (!allowedTools.has(toolRequest.name) || !spec.capabilities.includes(toolRequest.name)) {
      toolResult = {tool: toolRequest.name, verified: true, ok: false, code: 'FORBIDDEN', message: 'Dynamic Sub-Agent запросил инструмент вне scoped read-only capabilities'};
    } else if (seenCalls.has(signature)) {
      toolResult = {tool: toolRequest.name, verified: true, ok: false, code: 'DUPLICATE_TOOL_CALL', message: 'Повторный вызов Dynamic Sub-Agent не выполнен'};
    } else {
      seenCalls.add(signature);
      budget.remainingToolTurns -= 1;
      send({type: 'tool', phase: 'start', role: 'subagent', agentId: spec.agentId, agentName: spec.role, name: toolRequest.name});
      toolResult = safeToolResult(toolRequest.name, await invokeTool({spec, name: toolRequest.name, arguments: toolRequest.arguments}));
    }
    toolResults.push(toolResult);
    send({
      type: 'tool', phase: 'result', role: 'subagent',
      agentId: spec.agentId, agentName: spec.role, name: toolRequest.name,
      ok: toolResult.ok === true, code: toolResult.code || null,
      additions: 0, deletions: 0, files: [],
      ...stepIo(toolRequest, toolResult),
    });
  }

  if (parseDynamicSubagentToolRequest(raw)) throw new Error('WAI_SUBAGENT_TOOL_PROTOCOL_INVALID');
  const parsed = parseObject(raw);
  if (!parsed || parsed.wesiTool) throw new Error('WAI_SUBAGENT_RESULT_INVALID');
  const result = validateDynamicSubagentResult(parsed, spec);
  const workspaceResult = applySubagentWorkspaceEdits(workspace, {
    agentId: spec.agentId,
    allowedPaths: spec.workspace.writablePaths,
    edits: result.workspaceEdits,
  });
  if (workspaceResult.conflicts.length) {
    send(buildDynamicSubagentEvent(spec, 'conflict', {label: `${spec.role}: workspace conflict`, detail: `${workspaceResult.conflicts.length} stale/overlapping edits rejected; Lead will resolve.`}));
  } else if (workspaceResult.applied.length) {
    send(buildDynamicSubagentEvent(spec, 'workspace', {label: `${spec.role}: workspace`, detail: `${workspaceResult.applied.length} revision-safe edits accepted.`}));
  }
  send(buildDynamicSubagentEvent(spec, 'result', {
    label: `${spec.role} · готово`,
    detail: visibleSnippet(result.summary, 300) || 'Результат передан ведущей персоне.',
  }));
  const visibleResult = visibleSnippet([result.summary, result.recommendation].filter(Boolean).join(' '), 520);
  send(reasoningEvent(
    `Что дал ${spec.role}`,
    visibleResult || 'Независимая проверка завершена; её выводы учту при сборке итогового ответа.',
  ));
  return {ok: true, spec, result, toolResults, workspaceResult};
}

export async function runDynamicSubagents({prepared, invokeModel, invokeTool, emit, signal}) {
  const policy = prepared?.subagents;
  if (!policy || policy.enabled !== true) return {ok: false, skipped: true, reason: policy?.reason || 'disabled'};
  if (typeof invokeModel !== 'function' || typeof invokeTool !== 'function') throw new Error('WAI_SUBAGENT_RUNTIME_INVALID');
  if (signal?.aborted) throw new Error('WAI_SUBAGENT_CANCELLED');

  const send = typeof emit === 'function' ? emit : () => {};
  const workspace = createConflictSafeWorkspace({workspaceId: `${prepared.requestId}:workspace`, files: policy.workspaceFiles});
  const manualRequest = parseManualSubagentRequest(prepared.message);
  let planRaw = '';
  if (manualRequest) {
    planRaw = JSON.stringify({
      subagents: [{
        role: manualRequest.role,
        task: manualRequest.task,
        requestedCapabilities: Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames : [],
      }],
    });
  } else {
    planRaw = await invokeModel({actor: 'lead', phase: 'subagent-plan', input: plannerInput(prepared, policy)});
  }
  const specs = sanitizePlan(planRaw, prepared, policy, workspace);
  if (!specs.length) return {ok: true, skipped: true, reason: 'planner_selected_none', results: [], workspace: workspaceSnapshot(workspace)};

  for (const spec of specs) {
    send(buildDynamicSubagentEvent(spec, 'planned', {
      label: `Зову специалиста · ${spec.role}`,
      detail: `Поручаю: ${visibleSnippet(spec.task, 300)}`,
    }));
    send(reasoningEvent(
      `Зачем нужен ${spec.role}`,
      `Поручу ему отдельную проверку: ${visibleSnippet(spec.task, 420)}`,
    ));
  }

  const budget = {remainingToolTurns: Math.max(0, Math.min(12, Number(policy.maxTotalToolTurns || 0) || 0))};
  const results = [];
  for (const spec of specs) {
    if (signal?.aborted) throw new Error('WAI_SUBAGENT_CANCELLED');
    try {
      results.push(await runOneSubagent({spec, policy, workspace, invokeModel, invokeTool, emit: send, signal, budget}));
    } catch (error) {
      if (signal?.aborted) throw error;
      send(buildDynamicSubagentEvent(spec, 'fallback', {label: `${spec.role}: недоступен`, detail: 'Lead продолжит без результата этого временного специалиста.'}));
      results.push({ok: false, spec, code: String(error?.message || 'WAI_SUBAGENT_FAILED').slice(0, 120)});
    }
  }

  return {
    ok: true,
    skipped: false,
    results,
    workspace: workspaceSnapshot(workspace),
    remainingToolTurns: budget.remainingToolTurns,
  };
}
