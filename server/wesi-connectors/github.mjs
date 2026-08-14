import crypto from 'node:crypto';
import {getCredential, putCredential, deleteCredential} from './vault.mjs';
import {Permission, requirePermission, assertSafeGitHubWrite} from './policy.mjs';

const API = 'https://api.github.com';
const OAUTH = 'https://github.com/login/oauth';

function clientId() {
  const value = String(process.env.WESI_GITHUB_CLIENT_ID || '');
  if (!value) throw Object.assign(new Error('GITHUB_CONNECTOR_NOT_CONFIGURED'), {code: 'GITHUB_CONNECTOR_NOT_CONFIGURED'});
  return value;
}

function clientSecret() {
  const value = String(process.env.WESI_GITHUB_CLIENT_SECRET || '');
  if (!value) throw Object.assign(new Error('GITHUB_CONNECTOR_NOT_CONFIGURED'), {code: 'GITHUB_CONNECTOR_NOT_CONFIGURED'});
  return value;
}

export function beginOAuth(ownerId, redirectUri, stateStore) {
  const state = crypto.randomBytes(24).toString('base64url');
  stateStore.set(state, {ownerId: String(ownerId), redirectUri: String(redirectUri), expiresAt: Date.now() + 10 * 60_000});
  const url = new URL(`${OAUTH}/authorize`);
  url.searchParams.set('client_id', clientId());
  url.searchParams.set('redirect_uri', String(redirectUri));
  url.searchParams.set('scope', 'repo read:user workflow');
  url.searchParams.set('state', state);
  return {url: url.toString(), state};
}

export async function finishOAuth({code, state, stateStore}) {
  const pending = stateStore.get(String(state));
  stateStore.delete(String(state));
  if (!pending || pending.expiresAt < Date.now()) throw Object.assign(new Error('INVALID_OAUTH_STATE'), {code: 'INVALID_OAUTH_STATE'});
  const response = await fetch(`${OAUTH}/access_token`, {
    method: 'POST',
    headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    body: JSON.stringify({client_id: clientId(), client_secret: clientSecret(), code: String(code), redirect_uri: pending.redirectUri}),
  });
  const payload = await response.json().catch(() => ({}));
  const token = String(payload.access_token || '');
  if (!response.ok || !token) throw Object.assign(new Error('GITHUB_OAUTH_EXCHANGE_FAILED'), {code: 'GITHUB_OAUTH_EXCHANGE_FAILED'});
  const user = await githubRequestWithToken(token, 'GET', '/user');
  putCredential(pending.ownerId, 'github', token, {
    login: String(user.login || ''),
    avatarUrl: String(user.avatar_url || ''),
    scopes: String(response.headers.get('x-oauth-scopes') || payload.scope || '').split(',').map(v => v.trim()).filter(Boolean),
  });
  return {ownerId: pending.ownerId, login: String(user.login || '')};
}

async function githubRequestWithToken(token, method, pathname, body) {
  const response = await fetch(`${API}${pathname}`, {
    method,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Wesi-AI-Connector/1.0',
      ...(body == null ? {} : {'Content-Type': 'application/json'}),
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch { payload = {text}; }
  if (!response.ok) {
    const error = new Error(`GITHUB_HTTP_${response.status}`);
    error.code = `GITHUB_HTTP_${response.status}`;
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

export async function request(ownerId, method, pathname, body, policy = {}) {
  const record = getCredential(ownerId, 'github');
  if (!record) throw Object.assign(new Error('GITHUB_NOT_CONNECTED'), {code: 'GITHUB_NOT_CONNECTED'});
  const verb = String(method || 'GET').toUpperCase();
  const path = String(pathname || '');
  if (!/^\/(user|repos\/[-A-Za-z0-9_.]+\/[-A-Za-z0-9_.]+)(\/|$)/.test(path)) {
    throw Object.assign(new Error('GITHUB_PATH_NOT_ALLOWED'), {code: 'GITHUB_PATH_NOT_ALLOWED'});
  }
  if (verb === 'GET' || verb === 'HEAD') requirePermission('github', Permission.READ, policy);
  else assertSafeGitHubWrite({method: verb, path, policy});
  return githubRequestWithToken(record.secret, verb, path, body);
}

export function status(ownerId) {
  const record = getCredential(ownerId, 'github');
  return record ? {connected: true, metadata: record.metadata || {}, updatedAt: record.updatedAt} : {connected: false};
}

export function disconnect(ownerId) {
  return {disconnected: deleteCredential(ownerId, 'github')};
}
