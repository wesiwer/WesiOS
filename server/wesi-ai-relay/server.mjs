import http from 'node:http';
import {verifyMainRequest} from './auth.mjs';
import {parseGoogleRoute, callGoogleText} from './google.mjs';

const host = process.env.WESI_RELAY_HOST || '127.0.0.1';
const port = Number(process.env.WESI_RELAY_PORT || 8787);
const secret = String(process.env.WESI_MAIN_SHARED_SECRET || '');
const googleKey = String(process.env.GEMINI_API_KEY || '');

function send(res, status, body) {
  res.writeHead(status, {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 2097152) throw new Error('too_large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, {ok: true, service: 'wesi-ai-relay'});
  if (req.method !== 'POST' || req.url !== '/v1/wesi-ai') return send(res, 404, {ok: false, code: 'NOT_FOUND'});

  let raw;
  try { raw = await readBody(req); }
  catch { return send(res, 413, {ok: false, code: 'WAI_RELAY_BODY_TOO_LARGE'}); }

  const auth = verifyMainRequest(req.headers, raw, secret);
  if (!auth.ok) return send(res, auth.code === 'WAI_RELAY_NOT_CONFIGURED' ? 503 : 401, auth);

  let request;
  try { request = JSON.parse(raw); }
  catch { return send(res, 400, {ok: false, code: 'WAI_RELAY_BAD_JSON'}); }

  if (String(request.requestId || '') !== auth.requestId) return send(res, 401, {ok: false, code: 'WAI_RELAY_AUTH_FAILED'});
  if (!['chat', 'lobby', 'route'].includes(request.operation)) return send(res, 400, {ok: false, code: 'WAI_OPERATION_UNAVAILABLE'});

  const route = parseGoogleRoute(request.route);
  if (!route) return send(res, 400, {ok: false, code: 'WAI_ROUTE_UNAVAILABLE'});

  try {
    const result = await callGoogleText(route.model, request.input || {}, googleKey);
    if (!result.ok) return send(res, result.status || 502, {ok: false, code: result.code});
    return send(res, 200, {ok: true, answer: result.answer});
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return send(res, 502, {ok: false, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'});
  }
}).listen(port, host, () => console.log(`Wesi AI Relay listening on ${host}:${port}`));
