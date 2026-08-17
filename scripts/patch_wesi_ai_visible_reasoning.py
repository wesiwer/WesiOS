from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one match, got {text.count(old)}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


gateway = 'server/wesi-ai-stream/gateway.mjs'
replace_once(
    gateway,
    "function writeNdjson(res, event) {\n  if (res.destroyed || res.writableEnded) return false;\n  res.write(`${JSON.stringify(event)}\\n`);\n  return true;\n}\n",
    "function writeNdjson(res, event) {\n  if (res.destroyed || res.writableEnded) return false;\n  res.write(`${JSON.stringify(event)}\\n`);\n  return true;\n}\n\nfunction compactVisibleText(value, max = 320) {\n  const text = String(value || '').replace(/\\s+/g, ' ').trim();\n  if (!text) return '';\n  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1)).trimEnd()}…`;\n}\n\nfunction personaRu(value) {\n  return String(value || '').trim().toLowerCase() === 'nirvana' ? 'Нирвана' : 'Зейн';\n}\n\nexport function visibleReasoningSummary(prepared = {}) {\n  const message = compactVisibleText(prepared.message, 180);\n  const normalized = message.toLowerCase().replace(/[!?.…]+$/g, '').trim();\n  const attachments = Array.isArray(prepared.attachments) ? prepared.attachments : [];\n  const greetingOnly = /^(привет|здравствуй|здравствуйте|добрый день|добрый вечер|доброе утро|хай|hello|hi|hey|ку|салют)$/i.test(normalized);\n  if (greetingOnly && !attachments.length) {\n    return 'Здесь всё просто: это приветствие, поэтому глубокая проверка не нужна. Отвечу коротко и естественно, чтобы продолжить разговор без лишней сложности.';\n  }\n\n  const parts = [];\n  if (message) parts.push(`Сначала разберусь, что именно нужно сделать в запросе «${message}».`);\n  if (attachments.length) parts.push(`Есть ${attachments.length} ${attachments.length === 1 ? 'вложение' : 'вложения'} — учту его содержимое до вывода.`);\n  if (prepared.coagent?.enabled === true) {\n    parts.push(`Задача затрагивает несколько областей, поэтому сверю свою оценку с ${personaRu(prepared.coagent.coagentPersona)} и возьму только полезные выводы.`);\n  }\n  if (prepared.subagents?.enabled === true) {\n    parts.push('Отдельные независимые проверки разнесу между временными специалистами, а итог соберу сам, чтобы не смешивать противоречащие выводы.');\n  } else {\n    parts.push('После этого дам прямой ответ, опираясь на доступный контекст и проверенные данные.');\n  }\n  return compactVisibleText(parts.join(' '), 760);\n}\n"
)

replace_once(
    gateway,
    "      writeNdjson(res, {\n        type: 'activity',\n        kind: 'reasoning',\n        phase: 'result',\n        label: 'Контекст подготовлен',\n        detail: 'История, память, проект и доступные инструменты проверены.',\n      });\n",
    "      writeNdjson(res, {\n        type: 'activity',\n        kind: 'reasoning',\n        phase: 'result',\n        label: 'Контекст подготовлен',\n        detail: 'История, память, проект и доступные инструменты проверены.',\n      });\n      writeNdjson(res, {\n        type: 'activity',\n        kind: 'reasoning',\n        phase: 'result',\n        label: 'Как я подхожу к запросу',\n        detail: visibleReasoningSummary(prepared),\n      });\n"
)

coagent = 'server/wesi-ai-stream/persona_coagent_orchestrator.mjs'
replace_once(
    coagent,
    "function timelineEvent(label, detail = '') {\n  return {\n    type: 'activity',\n    kind: 'reasoning',\n    phase: 'done',\n    label,\n    detail,\n  };\n}\n",
    "function timelineEvent(label, detail = '') {\n  return {\n    type: 'activity',\n    kind: 'reasoning',\n    phase: 'done',\n    label,\n    detail,\n  };\n}\n\nfunction visibleSnippet(value, max = 360) {\n  const text = String(value || '').replace(/\\s+/g, ' ').trim();\n  if (!text) return '';\n  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1)).trimEnd()}…`;\n}\n\nfunction humanReason(value) {\n  const key = String(value || '').trim();\n  const labels = {\n    joint_mode: 'нужна совместная проверка обеих специализаций',\n    cross_domain_product: 'в запросе пересекаются продуктовая и техническая части',\n    mixed_specializations: 'в задаче одновременно есть технические и творческие требования',\n    creative_review_needed: 'полезна независимая проверка UX/визуальной части',\n    technical_review_needed: 'полезна независимая техническая проверка',\n  };\n  return labels[key] || 'вторая специализация может заметить то, что легко пропустить одному агенту';\n}\n"
)
replace_once(
    coagent,
    "    reviewRound > 0\n      ? 'Lead запросил одну ограниченную правку результата.'\n      : 'Передан только ограниченный контекст задачи и разрешённые возможности.',\n",
    "    reviewRound > 0\n      ? `Нужно уточнить только один момент: ${visibleSnippet(policy.revisionRequest, 260) || 'Lead запросил точечную правку результата.'}`\n      : `Подключаю ${coagentLabel}, потому что ${humanReason(policy.reason)}. Его задача: ${visibleSnippet(handoff.task, 300)}`,\n"
)
replace_once(
    coagent,
    "  send(timelineEvent(\n    reviewRound > 0 ? `${coagentLabel} → ${leadLabel} · исправлено` : `${coagentLabel} → ${leadLabel}`,\n    'Структурированный результат передан Lead Persona для проверки и интеграции.',\n  ));\n",
    "  const visibleResult = visibleSnippet(\n    [result.summary, result.recommendation].filter(Boolean).join(' '),\n    520,\n  );\n  send(timelineEvent(\n    reviewRound > 0 ? `${coagentLabel} → ${leadLabel} · исправлено` : `${coagentLabel} → ${leadLabel}`,\n    visibleResult || 'Проверка завершена; полезные выводы переданы Lead для итогового ответа.',\n  ));\n"
)
replace_once(
    coagent,
    "    send(timelineEvent(\n      `${leadLabel} · результат принят`,\n      'Дополнительная правка Co-Agent не требуется.',\n    ));\n",
    "    send(timelineEvent(\n      `${leadLabel} · результат принят`,\n      `Вывод ${personaLabel(initial.handoff.coagentPersona)} согласуется с основной линией ответа; дополнительная правка не нужна.`,\n    ));\n"
)

dynamic = 'server/wesi-ai-stream/dynamic_subagent_orchestrator.mjs'
replace_once(
    dynamic,
    "function parseObject(value) {\n  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));\n  if (!text.startsWith('{') || !text.endsWith('}')) return null;\n  try {\n    const parsed = JSON.parse(text);\n    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;\n  } catch {\n    return null;\n  }\n}\n",
    "function parseObject(value) {\n  const text = stripOuterCodeFence(stripLeadingReasoningBlocks(value));\n  if (!text.startsWith('{') || !text.endsWith('}')) return null;\n  try {\n    const parsed = JSON.parse(text);\n    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;\n  } catch {\n    return null;\n  }\n}\n\nfunction visibleSnippet(value, max = 360) {\n  const text = String(value || '').replace(/\\s+/g, ' ').trim();\n  if (!text) return '';\n  return text.length <= max ? text : `${text.slice(0, Math.max(1, max - 1)).trimEnd()}…`;\n}\n\nfunction reasoningEvent(label, detail) {\n  return {type: 'activity', kind: 'reasoning', phase: 'done', label, detail};\n}\n"
)
replace_once(
    dynamic,
    "  for (const spec of specs) {\n    send(buildDynamicSubagentEvent(spec, 'planned', {label: `Специалист: ${spec.role}`, detail: 'Lead создал временного специалиста с depth=1 и ограниченным budget.'}));\n  }\n",
    "  for (const spec of specs) {\n    send(buildDynamicSubagentEvent(spec, 'planned', {label: `Специалист: ${spec.role}`, detail: 'Lead создал временного специалиста с ограниченным scope.'}));\n    send(reasoningEvent(\n      `Зачем нужен ${spec.role}`,\n      `Поручу ему отдельную проверку: ${visibleSnippet(spec.task, 420)}`,\n    ));\n  }\n"
)
replace_once(
    dynamic,
    "  send(buildDynamicSubagentEvent(spec, 'result', {label: `${spec.role}: готово`, detail: 'Структурированный результат передан Lead Coordinator.'}));\n  return {ok: true, spec, result, toolResults, workspaceResult};\n",
    "  send(buildDynamicSubagentEvent(spec, 'result', {label: `${spec.role}: готово`, detail: 'Результат передан Lead Coordinator.'}));\n  const visibleResult = visibleSnippet([result.summary, result.recommendation].filter(Boolean).join(' '), 520);\n  send(reasoningEvent(\n    `Что дал ${spec.role}`,\n    visibleResult || 'Независимая проверка завершена; её выводы учту при сборке итогового ответа.',\n  ));\n  return {ok: true, spec, result, toolResults, workspaceResult};\n"
)

# Tests for the new visible summary contract.
test_path = 'server/wesi-ai-stream/gateway.test.mjs'
replace_once(
    test_path,
    "import {createGateway, parseToolRequest, shouldRevealBufferedText, signRelayRequest} from './gateway.mjs';\n",
    "import {createGateway, parseToolRequest, shouldRevealBufferedText, signRelayRequest, visibleReasoningSummary} from './gateway.mjs';\n"
)
replace_once(
    test_path,
    "test('HMAC signing matches deterministic payload', () => {\n  const actual = signRelayRequest('rid', '123', '{\"x\":1}', 'secret');\n  assert.equal(actual, '00869641839c4678dd4316b6a4d07ced9cdd8b44751bb15286e4665e39093a78');\n});\n",
    "test('HMAC signing matches deterministic payload', () => {\n  const actual = signRelayRequest('rid', '123', '{\"x\":1}', 'secret');\n  assert.equal(actual, '00869641839c4678dd4316b6a4d07ced9cdd8b44751bb15286e4665e39093a78');\n});\n\ntest('visible reasoning summary is human and context-aware', () => {\n  const greeting = visibleReasoningSummary(prepared());\n  assert.match(greeting, /приветств/i);\n  assert.match(greeting, /коротко|естественно/i);\n\n  const complex = visibleReasoningSummary(preparedWithCoagent());\n  assert.match(complex, /Сделай приложение с хорошим UX/i);\n  assert.match(complex, /Нирван/i);\n  assert.doesNotMatch(complex, /chain.of.thought|budget|depth=/i);\n});\n"
)

print('VISIBLE_REASONING_PATCH_APPLIED')
