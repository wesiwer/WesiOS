import {
  createPersonaHandoff,
  validatePersonaCoagentResult,
  validateLeadReview,
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

export function parseLeadReviewResponse(value, handoff) {
  const parsed = parseObject(value);
  if (!parsed || parsed.wesiTool) throw new Error('WAI_COAGENT_REVIEW_INVALID');
  return validateLeadReview(parsed, handoff);
}

function personaLabel(value) {
  return String(value || '').trim().toLowerCase() === 'nirvana' ? 'Нирвана' : 'Зейн';
}

function timelineEvent(label, detail = '') {
  return {
    type: 'activity',
    kind: 'reasoning',
    phase: 'done',
    label,
    detail,
  };
}

function visibleSnippet(value, max = 360) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1)).trimEnd()}…`;
}

function humanReason(value) {
  const key = String(value || '').trim();
  const labels = {
    joint_mode: 'нужна совместная проверка обеих специализаций',
    cross_domain_product: 'в запросе пересекаются продуктовая и техническая части',
    mixed_specializations: 'в задаче одновременно есть технические и творческие требования',
    creative_review_needed: 'полезна независимая проверка UX/визуальной части',
    technical_review_needed: 'полезна независимая техническая проверка',
  };
  return labels[key] || 'вторая специализация может заметить то, что легко пропустить одному агенту';
}

function resultInstruction(reviewRound) {
  return '[WESI_AI_COAGENT_OUTPUT]\n' +
    'Верни ТОЛЬКО JSON без markdown и без скрытых рассуждений: ' +
    `{"summary":"...","findings":["..."],"risks":["..."],"recommendation":"...","artifacts":["..."],"reviewRound":${reviewRound}}. ` +
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

function modelInput(handoff, policy, toolResults, finalOnly, reviewRound) {
  const systemParts = [
    String(policy.systemPrompt || '').trim(),
    '[WESI_AI_PERSONA_COAGENT_HANDOFF]\n' + JSON.stringify(handoff),
    resultInstruction(reviewRound),
  ].filter(Boolean);
  const toolPart = toolInstruction(policy.toolDefinitions);
  if (toolPart && !finalOnly && reviewRound === 0) systemParts.push(toolPart);
  if (toolResults.length) {
    systemParts.push('[WESI_AI_VERIFIED_COAGENT_TOOL_RESULTS]\n' + JSON.stringify(toolResults));
  }
  if (finalOnly || reviewRound > 0) {
    systemParts.push('[WESI_AI_COAGENT_FINAL_ONLY]\nНе вызывай инструменты. Верни только structured result JSON.');
  }
  return {
    system: systemParts.join('\n\n'),
    message: handoff.task,
    history: [],
    attachments: [],
  };
}

function leadReviewInput(prepared, collaboration) {
  const leadLabel = personaLabel(collaboration.handoff.leadPersona);
  return {
    system: [
      ...(Array.isArray(prepared.systemParts) ? prepared.systemParts : []),
      '[WESI_AI_PERSONA_COAGENT_REVIEW]\n' + JSON.stringify(collaboration.result),
      '[WESI_AI_PERSONA_COAGENT_REVIEW_POLICY]\n' +
        `Ты ${leadLabel}, Lead Persona. Проверь только полезность, корректность и непротиворечивость структурированного результата Co-Agent для текущего пользовательского запроса. ` +
        'Не вызывай инструменты и не отвечай пользователю. Верни ТОЛЬКО JSON без markdown: ' +
        '{"decision":"accept"} либо {"decision":"revise","revisionRequest":"краткая конкретная правка"}. ' +
        'Не добавляй analysis/reasoning/chain_of_thought.',
    ].join('\n\n'),
    history: [],
    message: String(prepared.message || '').slice(0, 12000),
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

async function runAttempt({prepared, policy, invokeModel, invokeTool, emit, signal, reviewRound}) {
  const revisionContext = reviewRound > 0
    ? [{
        kind: 'project_context',
        label: 'Проверенная правка от Lead Persona',
        text: JSON.stringify({
          previousResult: policy.previousResult || null,
          revisionRequest: String(policy.revisionRequest || '').slice(0, 2000),
        }),
      }]
    : [];
  const handoff = createPersonaHandoff({
    parentRequestId: prepared.requestId,
    handoffId: String(policy.handoffId || '').trim() || `${prepared.requestId}:persona:${policy.coagentPersona}${reviewRound ? ':review:1' : ''}`,
    leadPersona: policy.leadPersona || prepared.persona,
    coagentPersona: policy.coagentPersona,
    task: policy.task,
    context: [...revisionContext, ...(Array.isArray(policy.context) ? policy.context : [])],
    requestedCapabilities: policy.requestedCapabilities,
    grantedCapabilities: policy.grantedCapabilities,
    allowlistedCapabilities: policy.allowlistedCapabilities,
    sideEffectCapabilities: policy.sideEffectCapabilities,
    maxReviewRounds: policy.maxReviewRounds,
    maxToolTurns: reviewRound > 0 ? 0 : policy.maxToolTurns,
  });

  const send = typeof emit === 'function' ? emit : () => {};
  const leadLabel = personaLabel(handoff.leadPersona);
  const coagentLabel = personaLabel(handoff.coagentPersona);
  const initialPhase = reviewRound > 0 ? 'revision' : 'handoff';
  send(buildCoagentEvent(handoff, initialPhase, {
    label: reviewRound > 0 ? `${coagentLabel}: уточнение` : `Передано ${coagentLabel}`,
    detail: reviewRound > 0 ? 'Один круг уточнения по замечаниям ведущего.' : handoffReason(policy.reason),
  }));
  send(timelineEvent(
    reviewRound > 0 ? `${leadLabel} → ${coagentLabel} · уточнение` : `${leadLabel} → ${coagentLabel}`,
    reviewRound > 0
      ? `Нужно уточнить только один момент: ${visibleSnippet(policy.revisionRequest, 260) || 'Lead запросил точечную правку результата.'}`
      : `Подключаю ${coagentLabel}, потому что ${humanReason(policy.reason)}. Его задача: ${visibleSnippet(handoff.task, 300)}`,
  ));
  send(buildCoagentEvent(handoff, 'start', {
    label: `${coagentLabel}: проверка`,
    detail: reviewRound > 0
      ? 'Co-Agent уточняет результат без инструментов.'
      : 'Co-Agent получил ограниченный контекст и read-only инструменты.',
  }));
  send(timelineEvent(
    `${coagentLabel} · Co-Agent проверка`,
    reviewRound > 0 ? 'Уточнение результата без новых действий.' : 'Независимая проверка своей специализации.',
  ));

  const toolResults = [];
  const seenCalls = new Set();
  const allowedTools = new Set(Array.isArray(policy.allowedToolNames) ? policy.allowedToolNames.map(String) : []);
  let raw = '';

  for (let turn = 0; turn <= handoff.limits.maxToolTurns; turn += 1) {
    if (signal?.aborted) throw new Error('WAI_COAGENT_CANCELLED');
    const finalOnly = reviewRound > 0 || turn >= handoff.limits.maxToolTurns;
    raw = await invokeModel({
      handoff,
      actor: 'coagent',
      phase: reviewRound > 0 ? 'revision' : (finalOnly ? 'final' : `tool-${turn + 1}`),
      input: modelInput(handoff, policy, toolResults, finalOnly, reviewRound),
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
  const validated = validatePersonaCoagentResult(parsed, handoff);
  const result = {...validated, reviewRound};
  send(buildCoagentEvent(handoff, 'result', {
    label: `${coagentLabel}: готово`,
    detail: 'Проверка завершена, структурированный результат передан Lead Persona.',
  }));
  const visibleResult = visibleSnippet(
    [result.summary, result.recommendation].filter(Boolean).join(' '),
    520,
  );
  send(timelineEvent(
    reviewRound > 0 ? `${coagentLabel} → ${leadLabel} · исправлено` : `${coagentLabel} → ${leadLabel}`,
    visibleResult || 'Проверка завершена; полезные выводы переданы Lead для итогового ответа.',
  ));
  return {ok: true, handoff, result, toolResults};
}

// Причина передачи слова теперь видна человеку в ходе мыслей, а не только в
// логах, поэтому код заменяется фразой. Незнакомый код лучше показать как
// есть, чем спрятать за общей отговоркой.
const HANDOFF_REASONS = {
  joint_mode: 'Запрошен совместный режим — отвечаем вдвоём.',
  cross_domain_product: 'Задача продуктовая: нужны обе специализации.',
  mixed_specializations: 'В запросе и техническая, и творческая часть.',
  creative_review_needed: 'Нужен взгляд со стороны творческой части.',
  technical_review_needed: 'Нужен взгляд со стороны технической части.',
  cross_specialty_review: 'Нужна проверка смежной специализацией.',
};

function handoffReason(reason) {
  const key = String(reason || '').trim();
  return HANDOFF_REASONS[key] || (key ? `Причина: ${key}` : 'Нужна проверка смежной специализацией.');
}

export async function runPersonaCoagent({prepared, invokeModel, invokeTool, emit, signal}) {
  const policy = prepared?.coagent;
  if (!policy || policy.enabled !== true) return {ok: false, skipped: true, reason: policy?.reason || 'disabled'};
  if (typeof invokeModel !== 'function' || typeof invokeTool !== 'function') throw new Error('WAI_COAGENT_RUNTIME_INVALID');
  if (signal?.aborted) throw new Error('WAI_COAGENT_CANCELLED');

  const send = typeof emit === 'function' ? emit : () => {};
  const initial = await runAttempt({
    prepared,
    policy,
    invokeModel,
    invokeTool,
    emit: send,
    signal,
    reviewRound: 0,
  });

  if (initial.handoff.limits.maxReviewRounds < 1) return initial;
  if (signal?.aborted) throw new Error('WAI_COAGENT_CANCELLED');

  const leadLabel = personaLabel(initial.handoff.leadPersona);
  send(buildCoagentEvent(initial.handoff, 'review', {
    label: `${leadLabel}: проверка результата`,
    detail: 'Lead проверяет структурированный результат Co-Agent.',
  }));
  send(timelineEvent(
    `${leadLabel} · проверка Co-Agent результата`,
    'Проверка полезности, корректности и непротиворечивости перед интеграцией.',
  ));
  const rawReview = await invokeModel({
    handoff: initial.handoff,
    actor: 'lead',
    phase: 'lead-review',
    input: leadReviewInput(prepared, initial),
  });
  const review = parseLeadReviewResponse(rawReview, initial.handoff);
  if (review.decision === 'accept') {
    send(timelineEvent(
      `${leadLabel} · результат принят`,
      `Вывод ${personaLabel(initial.handoff.coagentPersona)} согласуется с основной линией ответа; дополнительная правка не нужна.`,
    ));
    return {...initial, review};
  }

  const revisedPolicy = {
    ...policy,
    reviewRound: 1,
    maxToolTurns: 0,
    allowedToolNames: [],
    toolDefinitions: [],
    previousResult: initial.result,
    revisionRequest: review.revisionRequest,
    task: `${policy.task}\n\n[WESI_AI_LEAD_REVISION_REQUEST]\n${review.revisionRequest}`,
    handoffId: `${prepared.requestId}:persona:${policy.coagentPersona}:review:1`,
  };
  const revised = await runAttempt({
    prepared,
    policy: revisedPolicy,
    invokeModel,
    invokeTool,
    emit: send,
    signal,
    reviewRound: 1,
  });
  return {
    ...revised,
    review,
    previousResult: initial.result,
    toolResults: initial.toolResults,
  };
}
