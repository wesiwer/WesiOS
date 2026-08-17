import crypto from 'node:crypto';
import {runPersonaCoagent} from './persona_coagent_orchestrator.mjs';
import {runDynamicSubagents} from './dynamic_subagent_orchestrator.mjs';

export const MAX_STREAM_BODY_BYTES = 28 * 1024 * 1024;
export const MAX_TOOL_TURNS = 4;
export const MAX_TOOL_CLASSIFICATION_BYTES = 4096;

function safeCode(value, fallback = 'WAI_STREAM_FAILED') {
  const code = String(value || '').trim();
  return /^WAI_[A-Z0-9_]{3,80}$/.test(code) ? code : fallback;
}

export function diagnosticPayload({requestId = '', stage = 'STREAM_GATEWAY', component = 'Streaming gateway', operation = 'chat.stream', code = 'WAI_STREAM_FAILED', httpStatus = 502, lastSuccess = '', durationMs = 0, detail = ''} = {}) {
  return {requestId: String(requestId || '').slice(0, 180), stage: String(stage || 'STREAM_GATEWAY').slice(0, 80), component: String(component || 'Streaming gateway').slice(0, 120), operation: String(operation || 'chat.stream').slice(0, 120), code: safeCode(code), httpStatus: Number(httpStatus || 502), lastSuccess: String(lastSuccess || '').slice(0, 120), durationMs: Math.max(0, Number(durationMs || 0) || 0), detail: String(detail || '').slice(0, 500)};
}

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

function jsonObjectAt(text, start) {
  if (start < 0 || text[start] !== '{') return null;
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
    if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return {json: text.slice(start, index + 1), end: index + 1};
      }
      if (depth < 0) return null;
    }
  }
  return null;
}

function parseToolEnvelope(value) {
  try {
    const parsed = JSON.parse(value);
    const tool = parsed && typeof parsed.wesiTool === 'object' && !Array.isArray(parsed.wesiTool)
      ? parsed.wesiTool
      : null;
    if (!tool) return null;
    const name = String(tool.name || '').trim();
    const args = tool.arguments && typeof tool.arguments === 'object' && !Array.isArray(tool.arguments)
      ? tool.arguments
      : {};
    return name ? {name, arguments: args} : null;
  } catch {
    return null;
  }
}

function safeToolChatter(value) {
  const text = String(value || '')
    .replace(/```(?:json)?/gi, '')
    .trim();
  if (!text) return true;
  if (text.length > 240) return false;
  if (/(?:пример|например|формат|образец|example|format|sample)/i.test(text)) return false;
  return /(?:инструмент|вызов|использ|запущ|провер|получ|найд|посмотр|tool|call|invoke|use|run|check|fetch|look)/i.test(text);
}

export function hasToolProtocolMarker(answer) {
  return /(?:["']?wesiTool["']?\s*:)/.test(String(answer || ''));
}

export function parseToolRequest(answer) {
  let text = stripLeadingReasoningBlocks(answer);
  text = stripOuterCodeFence(text);

  const direct = parseToolEnvelope(text);
  if (direct) return direct;

  const start = text.indexOf('{');
  if (start < 0) return null;
  const candidate = jsonObjectAt(text, start);
  if (!candidate) return null;
  const prefix = text.slice(0, start);
  const suffix = text.slice(candidate.end);
  if (!safeToolChatter(prefix) || !safeToolChatter(suffix)) return null;
  return parseToolEnvelope(candidate.json);
}

export function shouldRevealBufferedText(buffer) {
  let trimmed = String(buffer || '').trimStart();
  if (!trimmed) return false;
  if (hasToolProtocolMarker(trimmed)) return false;
  if (trimmed.startsWith('```')) {
    const brace = trimmed.indexOf('{');
    if (brace < 0) return trimmed.length >= MAX_TOOL_CLASSIFICATION_BYTES;
    trimmed = trimmed.slice(brace);
  }
  if (!trimmed.startsWith('{')) return true;
  const candidate = jsonObjectAt(trimmed, 0);
  if (candidate) return parseToolRequest(trimmed) === null;
  return trimmed.length >= MAX_TOOL_CLASSIFICATION_BYTES;
}

export function signRelayRequest(requestId, timestamp, raw, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(`${requestId}.${timestamp}.${raw}`)
    .digest('hex');
}

async function readRequestBody(req, maxBytes = MAX_STREAM_BODY_BYTES) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) {
      const error = new Error('WAI_STREAM_BODY_TOO_LARGE');
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString('utf8');
  let json;
  try {
    json = JSON.parse(raw || '{}');
  } catch {
    const error = new Error('WAI_STREAM_BAD_JSON');
    error.status = 400;
    throw error;
  }
  if (!json || typeof json !== 'object' || Array.isArray(json)) {
    const error = new Error('WAI_STREAM_BAD_JSON');
    error.status = 400;
    throw error;
  }
  return json;
}

function authForwardHeaders(req, streamSecret) {
  const authorization = String(req.headers.authorization || '');
  const session = String(req.headers['x-wesios-session'] || '');
  return {
    'content-type': 'application/json',
    authorization,
    'x-wesios-session': session,
    'x-wesi-ai-stream-secret': streamSecret,
  };
}

async function postPocketBase({pocketBaseUrl, path, body, request, streamSecret, signal, fetchImpl}) {
  const response = await fetchImpl(`${pocketBaseUrl.replace(/\/$/, '')}${path}`, {
    method: 'POST',
    headers: authForwardHeaders(request, streamSecret),
    body: JSON.stringify(body),
    signal,
  });
  let data = {};
  try {
    data = await response.json();
  } catch {}
  if (!response.ok || data.ok !== true) {
    const error = new Error(safeCode(data.code, response.status === 401 ? 'WAI_STREAM_UNAUTHORIZED' : 'WAI_STREAM_MAIN_REJECTED'));
    error.status = response.status;
    const mainDetail = [
      typeof data?.message === 'string' ? data.message.trim() : '',
      data?.data && typeof data.data === 'object' && !Array.isArray(data.data)
        ? JSON.stringify(data.data).slice(0, 300)
        : '',
    ].filter(Boolean).join(' | ');
    error.diagnostic = data.diagnostic || diagnosticPayload({requestId: body?.requestId || '', stage: 'MAIN', component: 'WesiOS Main', operation: path, code: error.message, httpStatus: response.status, lastSuccess: 'STREAM_GATEWAY', detail: mainDetail});
    throw error;
  }
  return data;
}

async function* decodeNdjson(response) {
  if (!response.body) return;
  const decoder = new TextDecoder();
  let pending = '';
  for await (const chunk of response.body) {
    pending += decoder.decode(chunk, {stream: true});
    for (;;) {
      const index = pending.indexOf('\n');
      if (index < 0) break;
      const line = pending.slice(0, index).trim();
      pending = pending.slice(index + 1);
      if (!line) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        const error = new Error('WAI_STREAM_BAD_RELAY_EVENT');
        error.status = 502;
        throw error;
      }
      yield event;
    }
  }
  const tail = pending.trim();
  if (tail) {
    try {
      yield JSON.parse(tail);
    } catch {
      const error = new Error('WAI_STREAM_BAD_RELAY_EVENT');
      error.status = 502;
      throw error;
    }
  }
}

async function relayStream({relayUrl, relaySecret, payload, signal, fetchImpl, onDelta}) {
  const raw = JSON.stringify(payload);
  const requestId = String(payload.requestId || '');
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = signRelayRequest(requestId, timestamp, raw, relaySecret);
  const response = await fetchImpl(`${relayUrl.replace(/\/$/, '')}/v1/wesi-ai-stream`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-wesi-request-id': requestId,
      'x-wesi-timestamp': timestamp,
      'x-wesi-signature': signature,
    },
    body: raw,
    signal,
  });
  if (!response.ok) {
    let data = {};
    try { data = await response.json(); } catch {}
    const error = new Error(safeCode(data.code, 'WAI_STREAM_RELAY_REJECTED'));
    error.status = response.status;
    error.diagnostic = data.diagnostic || diagnosticPayload({requestId, stage: 'RELAY', component: 'Foreign Relay', operation: 'provider.stream', code: error.message, httpStatus: response.status, lastSuccess: 'STREAM_GATEWAY'});
    throw error;
  }
  let finalEvent = null;
  for await (const event of decodeNdjson(response)) {
    const type = String(event?.type || '');
    if (type === 'delta') {
      const text = String(event.text || '');
      if (text) onDelta(text);
      continue;
    }
    if (type === 'done') {
      finalEvent = event;
      continue;
    }
    if (type === 'error') {
      const error = new Error(safeCode(event.code, 'WAI_PROVIDER_UNAVAILABLE'));
      error.status = Number(event.status || 502);
      error.diagnostic = event.diagnostic || diagnosticPayload({requestId, stage: 'PROVIDER', component: String(event.provider || 'AI provider'), operation: 'model.stream', code: error.message, httpStatus: error.status, lastSuccess: 'RELAY_CONNECTED'});
      throw error;
    }
  }
  if (!finalEvent) {
    const error = new Error('WAI_STREAM_RELAY_EOF');
    error.status = 502;
    throw error;
  }
  return finalEvent;
}

function writeNdjson(res, event) {
  if (res.destroyed || res.writableEnded) return false;
  res.write(`${JSON.stringify(event)}\n`);
  return true;
}

function diffStatsFromToolResult(toolResult) {
  const payload = toolResult && typeof toolResult.result === 'object' && !Array.isArray(toolResult.result)
    ? toolResult.result
    : {};
  const additions = Math.max(0, Number(payload.additions || toolResult?.additions || 0) || 0);
  const deletions = Math.max(0, Number(payload.deletions || toolResult?.deletions || 0) || 0);
  const rawFiles = Array.isArray(payload.files) ? payload.files : (Array.isArray(toolResult?.files) ? toolResult.files : []);
  const files = rawFiles.slice(0, 40).map((item) => {
    if (item && typeof item === 'object') return String(item.path || item.filename || item.name || '').slice(0, 500);
    return String(item || '').slice(0, 500);
  }).filter(Boolean);
  return {additions, deletions, files};
}

function aggregateDiffStats(toolResults) {
  let additions = 0;
  let deletions = 0;
  const files = new Set();
  for (const result of toolResults) {
    const stats = diffStatsFromToolResult(result);
    additions += stats.additions;
    deletions += stats.deletions;
    for (const file of stats.files) files.add(file);
  }
  return {additions, deletions, files: [...files].slice(0, 80)};
}

function relayPayload(prepared, toolResults, phase, finalOnly = false) {
  const requestId = `${prepared.requestId}_${phase}`;
  const systemParts = [...prepared.systemParts];
  if (toolResults.length) {
    systemParts.push(`[WESI_AI_VERIFIED_TOOL_RESULTS]\n${JSON.stringify(toolResults)}`);
  }
  if (finalOnly) {
    systemParts.push('[WESI_AI_FINAL_RESPONSE]\nЛимит инструментов исчерпан. Не вызывай инструменты снова. Дай только финальный ответ по verified results.');
  }
  return {
    requestId,
    route: prepared.route,
    operation: 'chat.stream',
    input: {
      system: systemParts.join('\n\n'),
      history: prepared.history,
      message: prepared.message,
      attachments: prepared.attachments,
    },
  };
}

async function streamOneTurn({prepared, toolResults, phase, finalOnly, relayUrl, relaySecret, signal, fetchImpl, res}) {
  let full = '';
  let buffer = '';
  let emitted = false;
  const onDelta = (text) => {
    full += text;
    buffer += text;

    const brace = buffer.indexOf('{');
    if (brace < 0) {
      if (buffer) {
        emitted = writeNdjson(res, {type: 'delta', text: buffer}) || emitted;
        buffer = '';
      }
      return;
    }
    if (brace > 0) {
      const prefix = buffer.slice(0, brace);
      if (prefix) emitted = writeNdjson(res, {type: 'delta', text: prefix}) || emitted;
      buffer = buffer.slice(brace);
    }
    if (shouldRevealBufferedText(buffer)) {
      emitted = writeNdjson(res, {type: 'delta', text: buffer}) || emitted;
      buffer = '';
    }
  };
  await relayStream({
    relayUrl,
    relaySecret,
    payload: relayPayload(prepared, toolResults, phase, finalOnly),
    signal,
    fetchImpl,
    onDelta,
  });
  return {
    full,
    buffer,
    emitted,
    toolRequest: parseToolRequest(full),
    invalidToolProtocol: hasToolProtocolMarker(full) && !parseToolRequest(full),
  };
}

export function createGateway(options = {}) {
  const pocketBaseUrl = String(options.pocketBaseUrl || process.env.WESI_POCKETBASE_URL || 'http://127.0.0.1:8090');
  const relayUrl = String(options.relayUrl || process.env.WESI_RELAY_URL || '');
  const streamSecret = String(options.streamSecret || process.env.WESI_STREAM_SECRET || '');
  const relaySecret = String(options.relaySecret || process.env.WESI_MAIN_SHARED_SECRET || '');
  const fetchImpl = options.fetchImpl || fetch;

  if (!/^https?:\/\//.test(pocketBaseUrl) || !/^https:\/\//.test(relayUrl) || streamSecret.length < 32 || relaySecret.length < 32) {
    throw new Error('WAI_STREAM_GATEWAY_NOT_CONFIGURED');
  }

  return async function handle(req, res) {
    const requestStartedAt = Date.now();
    let activeRequestId = '';
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
      res.end(JSON.stringify({ok: true, ready: true, service: 'wesi-ai-stream-gateway', streaming: true}));
      return;
    }
    if (req.method !== 'POST' || req.url !== '/api/wesi/ai/chat/stream') {
      res.writeHead(404, {'content-type': 'application/json; charset=utf-8'});
      res.end(JSON.stringify({ok: false, code: 'NOT_FOUND'}));
      return;
    }

    const abort = new AbortController();
    req.on('aborted', () => abort.abort());
    res.on('close', () => {
      if (!res.writableEnded) abort.abort();
    });

    try {
      const body = await readRequestBody(req);
      const preparedResponse = await postPocketBase({
        pocketBaseUrl,
        path: '/api/wesi/ai/stream/prepare-v2',
        body,
        request: req,
        streamSecret,
        signal: abort.signal,
        fetchImpl,
      });
      const prepared = preparedResponse.prepared;
    if (!prepared || typeof prepared !== 'object') throw new Error('WAI_STREAM_BAD_PREPARE');
    activeRequestId = String(prepared.requestId || '');

      res.writeHead(200, {
        'content-type': 'application/x-ndjson; charset=utf-8',
        'cache-control': 'no-store, no-transform',
        'x-content-type-options': 'nosniff',
        'x-accel-buffering': 'no',
        connection: 'keep-alive',
      });
      writeNdjson(res, {
        type: 'meta',
        requestId: prepared.requestId,
        persona: prepared.persona,
        tier: prepared.tier,
      });
      writeNdjson(res, {
        type: 'agent',
        phase: 'start',
        name: prepared.persona,
        role: 'lead',
      });
      writeNdjson(res, {
        type: 'activity',
        kind: 'reasoning',
        phase: 'result',
        label: 'Контекст подготовлен',
        detail: 'История, память, проект и доступные инструменты проверены.',
      });

      let leadPrepared = prepared;
      if (prepared.coagent?.enabled === true) {
        try {
          const collaboration = await runPersonaCoagent({
            prepared,
            signal: abort.signal,
            emit: (event) => writeNdjson(res, event),
            invokeModel: async ({handoff, phase, input}) => {
              let buffered = '';
              const finalEvent = await relayStream({
                relayUrl,
                relaySecret,
                payload: {
                  requestId: `${prepared.requestId}_coagent_${handoff.coagentPersona}_${phase}`,
                  route: prepared.route,
                  operation: 'chat.stream',
                  input,
                },
                signal: abort.signal,
                fetchImpl,
                onDelta: (text) => { buffered += text; },
              });
              return buffered || String(finalEvent?.answer || '');
            },
            invokeTool: async ({handoff, name, arguments: args}) => {
              const toolResponse = await postPocketBase({
                pocketBaseUrl,
                path: '/api/wesi/ai/stream/tool-v2',
                body: {
                  name,
                  arguments: args,
                  activeOrganizationId: prepared.activeOrganizationId,
                  requestId: prepared.requestId,
                  conversationId: prepared.conversationId,
                  persona: handoff.coagentPersona,
                  actorRole: 'coagent',
                  leadPersona: handoff.leadPersona,
                  handoffId: handoff.handoffId,
                },
                request: req,
                streamSecret,
                signal: abort.signal,
                fetchImpl,
              });
              return toolResponse.toolResult;
            },
          });
          if (collaboration.ok === true) {
            leadPrepared = {
              ...prepared,
              systemParts: [
                ...prepared.systemParts,
                `[WESI_AI_VERIFIED_COAGENT_RESULT]\n${JSON.stringify({
                  protocol: collaboration.result.protocol,
                  handoffId: collaboration.result.handoffId,
                  persona: collaboration.result.persona,
                  summary: collaboration.result.summary,
                  findings: collaboration.result.findings,
                  risks: collaboration.result.risks,
                  recommendation: collaboration.result.recommendation,
                  artifacts: collaboration.result.artifacts,
                  finalOwner: collaboration.result.finalOwner,
                })}`,
              ],
            };
            writeNdjson(res, {
              type: 'activity',
              kind: 'reasoning',
              phase: 'result',
              label: 'Co-Agent review готов',
              detail: 'Проверенный результат второй Persona Agent передан Lead для интеграции.',
            });
          }
        } catch (coagentError) {
          if (abort.signal.aborted) throw coagentError;
          writeNdjson(res, {
            type: 'agent',
            phase: 'fallback',
            role: 'coagent',
            name: String(prepared.coagent?.coagentPersona || ''),
            lead: prepared.persona,
            label: 'Co-Agent недоступен',
            detail: 'Lead продолжает выполнение самостоятельно.',
          });
        }
      }

      if (leadPrepared.subagents?.enabled === true) {
        try {
          const dynamic = await runDynamicSubagents({
            prepared: leadPrepared,
            signal: abort.signal,
            emit: (event) => writeNdjson(res, event),
            invokeModel: async ({spec, actor, phase, input}) => {
              let buffered = '';
              const identity = spec?.agentId || actor || 'planner';
              const safeIdentity = String(identity).replace(/[^a-zA-Z0-9_.:-]/g, '_').slice(0, 120);
              const finalEvent = await relayStream({
                relayUrl,
                relaySecret,
                payload: {
                  requestId: `${prepared.requestId}_subagent_${safeIdentity}_${phase}`,
                  route: prepared.route,
                  operation: 'chat.stream',
                  input,
                },
                signal: abort.signal,
                fetchImpl,
                onDelta: (text) => { buffered += text; },
              });
              return buffered || String(finalEvent?.answer || '');
            },
            invokeTool: async ({spec, name, arguments: args}) => {
              const toolResponse = await postPocketBase({
                pocketBaseUrl,
                path: '/api/wesi/ai/stream/tool-v2',
                body: {
                  name,
                  arguments: args,
                  activeOrganizationId: prepared.activeOrganizationId,
                  requestId: prepared.requestId,
                  conversationId: prepared.conversationId,
                  persona: prepared.persona,
                  actorRole: 'subagent',
                  leadPersona: prepared.persona,
                  handoffId: spec.agentId,
                },
                request: req,
                streamSecret,
                signal: abort.signal,
                fetchImpl,
              });
              return toolResponse.toolResult;
            },
          });
          const accepted = Array.isArray(dynamic.results)
            ? dynamic.results.filter((item) => item?.ok === true).map((item) => ({
                agentId: item.result.agentId,
                role: item.result.role,
                summary: item.result.summary,
                findings: item.result.findings,
                risks: item.result.risks,
                recommendation: item.result.recommendation,
                workspace: {
                  applied: item.workspaceResult?.applied || [],
                  conflicts: item.workspaceResult?.conflicts || [],
                  rejected: item.workspaceResult?.rejected || [],
                },
                finalOwner: item.result.finalOwner,
              }))
            : [];
          if (dynamic.ok === true && accepted.length) {
            leadPrepared = {
              ...leadPrepared,
              systemParts: [
                ...leadPrepared.systemParts,
                `[WESI_AI_VERIFIED_DYNAMIC_SUBAGENT_RESULTS]\n${JSON.stringify({
                  protocol: 'wesi.dynamic-subagent.v1',
                  results: accepted,
                  workspace: dynamic.workspace || null,
                  remainingToolTurns: dynamic.remainingToolTurns,
                  finalOwner: 'lead',
                })}`,
              ],
            };
            writeNdjson(res, {
              type: 'activity',
              kind: 'reasoning',
              phase: 'result',
              label: 'Dynamic specialists готовы',
              detail: `${accepted.length} временных специалистов завершили ограниченную проверку; результаты переданы Lead.`,
            });
          }
        } catch (subagentError) {
          if (abort.signal.aborted) throw subagentError;
          writeNdjson(res, {
            type: 'agent',
            phase: 'fallback',
            role: 'subagent',
            name: 'Dynamic specialists',
            lead: prepared.persona,
            label: 'Dynamic specialists недоступны',
            detail: 'Lead продолжает выполнение самостоятельно.',
          });
        }
      }

      const toolResults = [];
      const seenCalls = new Set();
      for (let turn = 0; turn < MAX_TOOL_TURNS; turn += 1) {
        const streamed = await streamOneTurn({
          prepared: leadPrepared,
          toolResults,
          phase: String(turn + 1),
          finalOnly: false,
          relayUrl,
          relaySecret,
          signal: abort.signal,
          fetchImpl,
          res,
        });
        const toolRequest = streamed.toolRequest;
        if (!toolRequest) {
          if (streamed.invalidToolProtocol) {
            toolResults.push({
              tool: 'wesi_tool_protocol',
              verified: true,
              ok: false,
              code: 'INVALID_TOOL_CALL',
              message: 'Служебный вызов инструмента не прошёл проверку формата и не был выполнен',
            });
            writeNdjson(res, {
              type: 'tool',
              phase: 'result',
              name: 'wesi_tool_protocol',
              ok: false,
              code: 'INVALID_TOOL_CALL',
              additions: 0,
              deletions: 0,
              files: [],
            });
            continue;
          }
          if (streamed.buffer) {
            writeNdjson(res, {type: 'delta', text: streamed.buffer});
          }
          const totalDiff = aggregateDiffStats(toolResults);
          writeNdjson(res, {
            type: 'agent',
            phase: 'result',
            name: prepared.persona,
            role: 'lead',
            ...(totalDiff.additions || totalDiff.deletions || totalDiff.files.length
              ? {additions: totalDiff.additions, deletions: totalDiff.deletions, files: totalDiff.files}
              : {}),
          });
          writeNdjson(res, {
            type: 'done',
            requestId: prepared.requestId,
            answer: streamed.full,
            toolResults,
          });
          res.end();
          return;
        }

        const signature = `${toolRequest.name}|${JSON.stringify(toolRequest.arguments)}`;
        let toolResult;
        if (seenCalls.has(signature)) {
          toolResult = {
            tool: toolRequest.name,
            verified: true,
            ok: false,
            code: 'DUPLICATE_TOOL_CALL',
            message: 'Повторный вызов не выполнен',
          };
        } else {
          seenCalls.add(signature);
          writeNdjson(res, {type: 'tool', phase: 'start', name: toolRequest.name});
          const toolResponse = await postPocketBase({
            pocketBaseUrl,
            path: '/api/wesi/ai/stream/tool-v2',
            body: {
              name: toolRequest.name,
              arguments: toolRequest.arguments,
              activeOrganizationId: prepared.activeOrganizationId,
              requestId: prepared.requestId,
              conversationId: prepared.conversationId,
              persona: prepared.persona,
              actorRole: 'lead',
              leadPersona: prepared.persona,
            },
            request: req,
            streamSecret,
            signal: abort.signal,
            fetchImpl,
          });
          toolResult = toolResponse.toolResult;
        }
        toolResults.push(toolResult);
        const diff = diffStatsFromToolResult(toolResult);
        const toolPayload = toolResult && typeof toolResult.result === 'object' && !Array.isArray(toolResult.result)
          ? toolResult.result
          : {};
        const hasDiffMetadata = Object.prototype.hasOwnProperty.call(toolPayload, 'additions') ||
          Object.prototype.hasOwnProperty.call(toolPayload, 'deletions') || diff.files.length > 0;
        writeNdjson(res, {
          type: 'tool',
          phase: 'result',
          name: toolRequest.name,
          ok: toolResult?.ok === true,
          code: toolResult?.code || null,
        ...(toolResult?.ok === true ? {} : {diagnostic: toolResult?.diagnostic || diagnosticPayload({requestId: prepared.requestId, stage: 'TOOL', component: toolRequest.name, operation: 'tool.execute', code: toolResult?.code || 'WAI_TOOL_FAILED', httpStatus: 500, lastSuccess: 'TOOL_DISPATCH', detail: toolResult?.message || ''})}),
        ...(hasDiffMetadata ? {additions: diff.additions, deletions: diff.deletions, files: diff.files} : {}),
          ...(Number.isFinite(Number(toolPayload.transactionCount)) ? {transactionCount: Number(toolPayload.transactionCount)} : {}),
          ...(toolPayload.organizationId ? {organizationId: String(toolPayload.organizationId)} : {}),
          ...(toolPayload.organizationName ? {organizationName: String(toolPayload.organizationName)} : {}),
        });
      }

      const finalStream = await streamOneTurn({
        prepared: leadPrepared,
        toolResults,
        phase: 'final',
        finalOnly: true,
        relayUrl,
        relaySecret,
        signal: abort.signal,
        fetchImpl,
        res,
      });
      if (finalStream.toolRequest || finalStream.invalidToolProtocol) {
        const error = new Error('WAI_TOOL_PROTOCOL_INVALID');
        error.status = 502;
        throw error;
      }
      if (finalStream.buffer) {
        writeNdjson(res, {type: 'delta', text: finalStream.buffer});
      }
      const totalDiff = aggregateDiffStats(toolResults);
      writeNdjson(res, {
        type: 'agent',
        phase: 'result',
        name: prepared.persona,
        role: 'lead',
        ...(totalDiff.additions || totalDiff.deletions || totalDiff.files.length
          ? {additions: totalDiff.additions, deletions: totalDiff.deletions, files: totalDiff.files}
          : {}),
      });
      writeNdjson(res, {
        type: 'done',
        requestId: prepared.requestId,
        answer: finalStream.full,
        toolResults,
      });
      res.end();
    } catch (error) {
      if (abort.signal.aborted || res.destroyed) return;
      const code = safeCode(error?.message, 'WAI_STREAM_FAILED');
    const status = Number(error?.status || 502);
    const diagnostic = error?.diagnostic || diagnosticPayload({requestId: activeRequestId, stage: 'STREAM_GATEWAY', component: 'Streaming gateway', operation: 'chat.stream', code, httpStatus: status, lastSuccess: activeRequestId ? 'MAIN_PREPARE' : 'CLIENT_AUTH', durationMs: Date.now() - requestStartedAt, detail: error?.name || ''});
    if (!res.headersSent) {
        res.writeHead(status >= 400 && status < 600 ? status : 502, {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        });
        res.end(JSON.stringify({ok: false, code, requestId: activeRequestId, diagnostic}));
      } else {
        writeNdjson(res, {type: 'error', code, status, requestId: activeRequestId, diagnostic});
        res.end();
      }
    }
  };
}
