from pathlib import Path

p = Path('scripts/patch_wesi_ai_dynamic_deliberation.py')
text = p.read_text(encoding='utf-8')
start = text.index("# 7) Integrate model-generated public deliberation into gateway.\n")
end = text.index("# 8) Deploy runtime includes the new module.\n")
replacement = r'''# 7) Integrate model-generated public deliberation into the CURRENT gateway.
gateway = 'server/wesi-ai-stream/gateway.mjs'
replace_once(
    gateway,
    "import {runDynamicSubagents} from './dynamic_subagent_orchestrator.mjs';\n",
    "import {runDynamicSubagents} from './dynamic_subagent_orchestrator.mjs';\nimport {\n  appendDeliberation,\n  createDeliberationState,\n  initialDeliberationInput,\n  parsePublicDeliberation,\n  reflectionInput,\n} from './public_deliberation.mjs';\n",
)

replace_once(
    gateway,
    "  const fetchImpl = options.fetchImpl || fetch;\n\n  if (!/^https?:\\/\\//.test(pocketBaseUrl)",
    "  const fetchImpl = options.fetchImpl || fetch;\n  const publicDeliberation = options.publicDeliberation !== false;\n\n  if (!/^https?:\\/\\//.test(pocketBaseUrl)",
)

replace_once(
    gateway,
    "export function createGateway(options = {}) {\n",
    r'''function publicNoteEvent(note) {
  return {
    type: 'activity',
    kind: 'reasoning',
    phase: 'done',
    label: String(note?.title || 'Промежуточный вывод').trim(),
    detail: String(note?.text || '').trim(),
    reasoningKind: String(note?.kind || '').trim(),
    publicDeliberation: true,
  };
}

async function bufferedPublicModel({relayUrl, relaySecret, prepared, input, requestId, signal, fetchImpl}) {
  let buffered = '';
  const finalEvent = await relayStream({
    relayUrl,
    relaySecret,
    payload: {
      requestId,
      route: prepared.route,
      operation: 'chat.stream',
      input,
    },
    signal,
    fetchImpl,
    onDelta: (text) => { buffered += text; },
  });
  return buffered || String(finalEvent?.answer || '').trim();
}

export function createGateway(options = {}) {
''',
)

replace_once(
    gateway,
    "      const body = await readRequestBody(req);\n      const preparedResponse = await postPocketBase({\n",
    "      const body = await readRequestBody(req);\n      const thinkingMode = body?.thinkingMode === true;\n      const preparedResponse = await postPocketBase({\n",
)

replace_once(
    gateway,
    "      writeNdjson(res, {\n        type: 'activity',\n        kind: 'reasoning',\n        phase: 'result',\n        label: 'Как я подхожу к запросу',\n        detail: visibleReasoningSummary(prepared),\n      });\n\n      let leadPrepared = prepared;\n",
    r'''      let deliberationState = null;
      if (publicDeliberation && thinkingMode) {
        try {
          const rawDeliberation = await bufferedPublicModel({
            relayUrl,
            relaySecret,
            prepared,
            input: initialDeliberationInput(prepared),
            requestId: `${prepared.requestId}_public_initial`,
            signal: abort.signal,
            fetchImpl,
          });
          const parsed = parsePublicDeliberation(rawDeliberation, {maxNotes: 4});
          if (parsed) {
            deliberationState = createDeliberationState(parsed);
            for (const note of deliberationState.notes) writeNdjson(res, publicNoteEvent(note));
          }
        } catch (deliberationError) {
          if (abort.signal.aborted) throw deliberationError;
        }
      }
      if (!deliberationState) {
        writeNdjson(res, {
          type: 'activity',
          kind: 'reasoning',
          phase: 'result',
          label: 'Как я подхожу к запросу',
          detail: visibleReasoningSummary(prepared),
          publicDeliberation: false,
        });
      }

      const reflectPublicly = async (evidence, suffix) => {
        if (!deliberationState || deliberationState.remaining <= 0) return;
        try {
          const rawReflection = await bufferedPublicModel({
            relayUrl,
            relaySecret,
            prepared,
            input: reflectionInput(prepared, deliberationState, evidence),
            requestId: `${prepared.requestId}_public_${suffix}`,
            signal: abort.signal,
            fetchImpl,
          });
          const parsed = parsePublicDeliberation(rawReflection, {
            maxNotes: Math.min(3, deliberationState.remaining),
          });
          if (!parsed) return;
          for (const note of appendDeliberation(deliberationState, parsed)) {
            writeNdjson(res, publicNoteEvent(note));
          }
        } catch (reflectionError) {
          if (abort.signal.aborted) throw reflectionError;
        }
      };

      let leadPrepared = prepared;
''',
)

replace_once(
    gateway,
    "            writeNdjson(res, {\n              type: 'activity',\n              kind: 'reasoning',\n              phase: 'result',\n              label: 'Co-Agent review готов',\n              detail: 'Проверенный результат второй Persona Agent передан Lead для интеграции.',\n            });\n",
    "            writeNdjson(res, {\n              type: 'activity',\n              kind: 'reasoning',\n              phase: 'result',\n              label: 'Co-Agent review готов',\n              detail: 'Проверенный результат второй Persona Agent передан Lead для интеграции.',\n            });\n            await reflectPublicly({\n              source: 'coagent',\n              persona: collaboration.result.persona || '',\n              summary: collaboration.result.summary || '',\n              findings: Array.isArray(collaboration.result.findings) ? collaboration.result.findings.slice(0, 5) : [],\n              risks: Array.isArray(collaboration.result.risks) ? collaboration.result.risks.slice(0, 5) : [],\n              recommendation: collaboration.result.recommendation || '',\n            }, 'coagent');\n",
)

replace_once(
    gateway,
    "            writeNdjson(res, {\n              type: 'activity',\n              kind: 'reasoning',\n              phase: 'result',\n              label: 'Dynamic specialists готовы',\n              detail: `${accepted.length} временных специалистов завершили ограниченную проверку; результаты переданы Lead.`,\n            });\n",
    "            writeNdjson(res, {\n              type: 'activity',\n              kind: 'reasoning',\n              phase: 'result',\n              label: 'Dynamic specialists готовы',\n              detail: `${accepted.length} временных специалистов завершили ограниченную проверку; результаты переданы Lead.`,\n            });\n            await reflectPublicly({source: 'specialists', results: accepted.map((item) => ({\n              role: item.role || '',\n              summary: item.summary || '',\n              findings: Array.isArray(item.findings) ? item.findings.slice(0, 4) : [],\n              risks: Array.isArray(item.risks) ? item.risks.slice(0, 4) : [],\n              recommendation: item.recommendation || '',\n            }))}, 'specialists');\n",
)

replace_once(
    gateway,
    "        writeNdjson(res, {\n          type: 'tool',\n          phase: 'result',\n          name: toolRequest.name,\n          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n        ...(toolResult?.ok === true ? {} : {diagnostic: toolResult?.diagnostic || diagnosticPayload({requestId: prepared.requestId, stage: 'TOOL', component: toolRequest.name, operation: 'tool.execute', code: toolResult?.code || 'WAI_TOOL_FAILED', httpStatus: 500, lastSuccess: 'TOOL_DISPATCH', detail: toolResult?.message || ''})}),\n        ...(hasDiffMetadata ? {additions: diff.additions, deletions: diff.deletions, files: diff.files} : {}),\n          ...(Number.isFinite(Number(toolPayload.transactionCount)) ? {transactionCount: Number(toolPayload.transactionCount)} : {}),\n          ...(toolPayload.organizationId ? {organizationId: String(toolPayload.organizationId)} : {}),\n          ...(toolPayload.organizationName ? {organizationName: String(toolPayload.organizationName)} : {}),\n        });\n",
    "        writeNdjson(res, {\n          type: 'tool',\n          phase: 'result',\n          name: toolRequest.name,\n          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n        ...(toolResult?.ok === true ? {} : {diagnostic: toolResult?.diagnostic || diagnosticPayload({requestId: prepared.requestId, stage: 'TOOL', component: toolRequest.name, operation: 'tool.execute', code: toolResult?.code || 'WAI_TOOL_FAILED', httpStatus: 500, lastSuccess: 'TOOL_DISPATCH', detail: toolResult?.message || ''})}),\n        ...(hasDiffMetadata ? {additions: diff.additions, deletions: diff.deletions, files: diff.files} : {}),\n          ...(Number.isFinite(Number(toolPayload.transactionCount)) ? {transactionCount: Number(toolPayload.transactionCount)} : {}),\n          ...(toolPayload.organizationId ? {organizationId: String(toolPayload.organizationId)} : {}),\n          ...(toolPayload.organizationName ? {organizationName: String(toolPayload.organizationName)} : {}),\n        });\n        await reflectPublicly({\n          source: 'tool',\n          tool: toolRequest.name,\n          ok: toolResult?.ok === true,\n          code: toolResult?.code || '',\n          message: String(toolResult?.message || '').slice(0, 1200),\n          additions: diff.additions,\n          deletions: diff.deletions,\n          files: diff.files.slice(0, 12),\n          transactionCount: Number.isFinite(Number(toolPayload.transactionCount)) ? Number(toolPayload.transactionCount) : null,\n          organizationName: toolPayload.organizationName ? String(toolPayload.organizationName) : '',\n        }, `tool_${turn + 1}`);\n",
)

'''
text = text[:start] + replacement + text[end:]
p.write_text(text, encoding='utf-8')
print('GATEWAY_PATCH_ALIGNED')
