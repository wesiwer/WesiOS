import {
  createPersonaHandoff,
  validatePersonaCoagentResult,
  buildCoagentEvent,
} from './persona_coagent.mjs';

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

function parseObject(value) {
  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function parseCoagentToolRequest(value) {
  const parsed = parseObject(value);
  const tool = parsed && typeof parsed.wesiTool === 'object' && !Array.isArray(parsed.wesiTool)
    ? parsed.wesiTool
    : null;
  if (!tool) return null;
  const name = String(tool.name || '').trim();
  const args = tool.arguments && typeof tool.arguments === 'object' && !Array.isArray(tool.arguments)
    ? tool.arguments
    : {};
  return name ? {name, arguments: args} : null;
}

function resultInstruction() {
  return '[WESI_AI_COAGENT_OUTPUT]\n' +
    'Верни ТОЛЬКО JSON без markdown и без скрытых рассуждений: ' +
    '{"summary":"...","findings":["..."],"risks":["..."],"recommendation":"...","artifacts":["..."]}. ' +
    'Не отвечай пользователю напрямую. Не добавляй analysis/reasoning/chain_of_thought поля.';
}

function toolInstruction(toolDefinitions) {
  if (!Array.isArray(toolDefinitions) || !toolDefinitions.length) return '';
  return '[WESI_AI_COAGENT_TOOL_PROTOCOL]\n' +
    'Разрешены только перечисленные read-only инструменты. Для вызова верни ТОЛЬКО JSON: ' +
    '{"wesiTool":{"name":"tool_name","arguments":{}}}. ' +
    'Никогда не считай действие выполненным без verified result. Нельзя создавать, изменять, удалять, подтверждать действия или делегировать работу дальше.\n' +
    JSON.stringify(toolDefinitions);
}

function modelInput(handoff, policy, toolResults, finalOnly) {
  const systemParts = [
    String(policy.systemPrompt || '').trim(),
    '[WESI_AI_PERSONA_COAGENT_HANDOFF]\n' + JSON.stringify(handoff),
    resultInstruction(),
  ].filter(Boolean);
  const toolPart = toolInstruction(policy.toolDefinitions);
  if (toolPart && !finalOnly) systemParts.push(toolPart);
  if (toolResults.length) {
    systemParts.push('[WESI_AI_VERIFIED_COAGENT_TOOL_RESULTS]\n' + JSON.stringify(toolResults));
  }
  if (finalOnly) {
    systemParts.push('[WESI_AI_COAGENT_FINAL_ONLY]\nЛимит инструментов исчерпан. Не вызывай инструменты. Верни только structured result JSON.');
  }
  return {
    system: systemParts.join('\n\n'),
    message: handoff.task,
    history: [],
    attachments: [],
  };
}

function safeToolResult(name, raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return {tool: name, verified: true, ok: false, code: 'COAGENT_TOOL_BAD_RESULT', message: 'Некорректный результат инструмента'};
  }
  return {
    ...raw,
    tool: String(raw.tool || name),
    verified: true,
  };
}

export async function runPersonaCoagent({prepared, invokeModel, invokeTool, emit, signal}) {
  const policy = prepared?.coagent;
  if (!policy || policy.enabled !== true) return {ok: false, skipped: true, reason: policy?.reason || 'disabled'};
  if (typeof invokeModel !== 'function' || typeof invokeTool !== 'function') throw new Error('WAI_COAGENT_RUNTIME_INVALID');
  if (signal?.aborted) throw new Error('WAI_COAGENT_CANCELLED');

  const handoff = createPersonaHandoff({
    parentRequestId: prepared.requestId,
    handoffId: `${prepared.requestId}:persona:${policy.coagentPersona}`,
    leadPersona: policy.leadPersona || prepared.persona,
    coagentPersona: policy.coagentPersona,
    task: policy.task,
    context: policy.context,
    requestedCapabilities: policy.requestedCapabilities,
    grantedCapabilities: policy.grantedCapabilities,
    allowlistedCapabilities: policy.allowlistedCapabilities,
    sideEffectCapabilities: policy.sideEffectCapabilities,
    maxReviewRounds: policy.maxReviewRounds,
    maxToolTurns: policy.maxToolTurns,
  });

  const send = typeof emit === 'function' ? emit : () => {};
  send(buildCoagentEvent(handoff, 'handoff', {
    label: `Передано ${handoff.coagentPersona}`,
    detail: policy.reason || 'cross_specialty_review',
  }));
  send(buildCoagentEvent(handoff, 'start', {
    label: `${handoff.coagentPersona}: проверка`,
    detail: 'Co-Agent получил ограниченный контекст и read-only инструменты.',
  }));

  const toolResults = [];
  const seenCalls = new Set();
  const allowedTools = new Set(Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames.map(String) : []);
  let raw = '';

  for (let turn = 0; turn <= handoff.limits.maxToolTurns; turn += 1) {
    if (signal?.aborted) throw new Error('WAI_COAGENT_CANCELLED');
    const finalOnly = turn >= handoff.limits.maxToolTurns;
    raw = await invokeModel({
      handoff,
      phase: finalOnly ? 'final' : `tool-${turn + 1}`,
      input: modelInput(handoff, policy, toolResults, finalOnly),
    });

    const toolRequest = parseCoagentToolRequest(raw);
    if (!toolRequest) break;
    if (finalOnly) throw new Error('WAI_COAGENT_TOOL_BUDGET_EXHAUSTED');

    const signature = `${toolRequest.name}|${JSON.stringify(toolRequest.arguments)}`;
    let toolResult;
    if (!allowedTools.has(toolRequest.name) || !handoff.capabilities.includes(toolRequest.name)) {
      toolResult = {
        tool: toolRequest.name,
        verified: true,
        ok: false,
        code: 'FORBIDDEN',
        message: 'Co-Agent запросил инструмент вне разрешённого read-only scope',
      };
    } else if (seenCalls.has(signature)) {
      toolResult = {
        tool: toolRequest.name,
        verified: true,
        ok: false,
        code: 'DUPLICATE_TOOL_CALL',
        message: 'Повторный вызов Co-Agent не выполнен',
      };
    } else {
      seenCalls.add(signature);
      send({type: 'tool', phase: 'start', role: 'coagent', persona: handoff.coagentPersona, handoffId: handoff.handoffId, name: toolRequest.name});
      toolResult = safeToolResult(toolRequest.name, await invokeTool({
        handoff,
        name: toolRequest.name,
        arguments: toolRequest.arguments,
      }));
    }
    toolResults.push(toolResult);
    send({
      type: 'tool',
      phase: 'result',
      role: 'coagent',
      persona: handoff.coagentPersona,
      handoffId: handoff.handoffId,
      name: toolRequest.name,
      ok: toolResult.ok === true,
      code: toolResult.code || null,
      additions: 0,
      deletions: 0,
      files: [],
    });
  }

  if (parseCoagentToolRequest(raw)) throw new Error('WAI_COAGENT_TOOL_PROTOCOL_INVALID');
  const parsed = parseObject(raw);
  if (!parsed || parsed.wesiTool) throw new Error('WAI_COAGENT_RESULT_INVALID');
  const result = validatePersonaCoagentResult(parsed, handoff);
  send(buildCoagentEvent(handoff, 'result', {
    label: `${handoff.coagentPersona}: готово`,
    detail: 'Проверка завершена, структурированный результат передан Lead Persona.',
  }));
  return {ok: true, handoff, result, toolResults};
}
