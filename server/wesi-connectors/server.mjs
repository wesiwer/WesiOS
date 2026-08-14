import http from 'node:http';
import {beginOAuth, finishOAuth, request as githubRequest, status as githubStatus, disconnect as githubDisconnect} from './github.mjs';

const HOST = process.env.WESI_CONNECTOR_HOST || '127.0.0.1';
const PORT = Number(process.env.WESI_CONNECTOR_PORT || 8791);
const SHARED = String(process.env.WESI_CONNECTOR_SHARED_SECRET || '');
const OAUTH_BASE = String(process.env.WESI_CONNECTOR_PUBLIC_BASE || '').replace(/\/$/, '');
const states = new Map();

function json(res, status, body) {
  const payload = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Content-Length': payload.length, 'Cache-Control': 'no-store'});
  res.end(payload);
}

async function readJson(req, max = 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > max) throw Object.assign(new Error('BODY_TOO_LARGE'), {status: 413});
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function authorize(req) {
  if (!SHARED || SHARED.length < 32) throw Object.assign(new Error('CONNECTOR_SHARED_SECRET_NOT_CONFIGURED'), {status: 503});
  const token = String(req.headers['x-wesi-connector-secret'] || '');
  if (token !== SHARED) throw Object.assign(new Error('UNAUTHORIZED'), {status: 401});
}

function ownerId(req) {
  const value = String(req.headers['x-wesi-owner-id'] || '').trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(value)) throw Object.assign(new Error('INVALID_OWNER'), {status: 400});
  return value;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://localhost');
  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, {ok: true, service: 'wesi-connectors', connectors: ['github']});
    }
    if (req.method === 'GET' && url.pathname === '/oauth/github/callback') {
      const result = await finishOAuth({code: url.searchParams.get('code'), state: url.searchParams.get('state'), stateStore: states});
      res.writeHead(302, {'Location': `${OAUTH_BASE || '/'}?connector=github&status=connected&login=${encodeURIComponent(result.login)}`, 'Cache-Control': 'no-store'});
      return res.end();
    }

    authorize(req);
    const owner = ownerId(req);

    if (req.method === 'POST' && url.pathname === '/v1/connectors/github/connect') {
      if (!OAUTH_BASE) return json(res, 503, {ok: false, code: 'CONNECTOR_PUBLIC_BASE_NOT_CONFIGURED'});
      const redirectUri = `${OAUTH_BASE}/oauth/github/callback`;
      const result = beginOAuth(owner, redirectUri, states);
      return json(res, 200, {ok: true, connector: 'github', authorizationUrl: result.url});
    }
    if (req.method === 'GET' && url.pathname === '/v1/connectors/github/status') {
      return json(res, 200, {ok: true, connector: 'github', ...githubStatus(owner)});
    }
    if (req.method === 'DELETE' && url.pathname === '/v1/connectors/github') {
      return json(res, 200, {ok: true, connector: 'github', ...githubDisconnect(owner)});
    }
    if (req.method === 'POST' && url.pathname === '/v1/connectors/github/request') {
      const body = await readJson(req);
      const result = await githubRequest(owner, body.method, body.path, body.body, body.policy || {});
      return json(res, 200, {ok: true, connector: 'github', result});
    }

    return json(res, 404, {ok: false, code: 'NOT_FOUND'});
  } catch (error) {
    const status = Number(error.status || 0) || (error.code === 'CONNECTOR_FORBIDDEN' ? 403 : 400);
    return json(res, Math.max(400, Math.min(status, 599)), {ok: false, code: String(error.code || error.message || 'CONNECTOR_ERROR')});
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Wesi Connectors listening on ${HOST}:${PORT}`);
});
