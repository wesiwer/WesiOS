from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def path(rel):
    return ROOT / rel


def read(rel):
    return path(rel).read_text(encoding="utf-8")


def write(rel, text):
    p = path(rel)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def replace_once(rel, old, new):
    text = read(rel)
    if old not in text:
        raise SystemExit(f"marker not found in {rel}: {old[:120]!r}")
    if text.count(old) != 1:
        raise SystemExit(f"marker is not unique in {rel}: {old[:120]!r}")
    write(rel, text.replace(old, new, 1))


def regex_once(rel, pattern, replacement):
    text = read(rel)
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"regex replacement failed in {rel}: {pattern}")
    write(rel, new)


TRANSPORT = r'''const ai = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_lib.js");

const MAX_SKEW_SECONDS = 300;
const ALLOWED_METHODS = [
  "sendMessage",
  "sendPhoto",
  "sendChatAction",
  "answerCallbackQuery",
  "deleteMessage",
  "deleteMessages",
];

function canonicalize(value) {
  if (value === null || value === undefined) return "null";
  if (Array.isArray(value)) {
    return "[" + value.map(canonicalize).join(",") + "]";
  }
  if (typeof value === "object") {
    const keys = Object.keys(value).sort();
    return "{" + keys.map((key) => JSON.stringify(key) + ":" + canonicalize(value[key])).join(",") + "}";
  }
  return JSON.stringify(value);
}

function relayConfig() {
  try { return ai.readRelayConfig(); }
  catch (_) { return {ready: false, url: "", sharedSecret: ""}; }
}

function telegramApi(cfg, method, payload) {
  const name = String(method || "");
  if (ALLOWED_METHODS.indexOf(name) < 0) {
    return {ok: false, code: "TELEGRAM_METHOD_FORBIDDEN"};
  }
  const relay = relayConfig();
  if (!cfg || cfg.ready !== true || !relay.ready) {
    return {ok: false, code: "TELEGRAM_NOT_CONFIGURED"};
  }

  const requestId = "wai_tg_" + Date.now() + "_" + $security.randomString(16);
  const request = {requestId: requestId, method: name, payload: payload || {}};
  const raw = JSON.stringify(request);
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = $security.hs256(requestId + "." + timestamp + "." + raw, relay.sharedSecret);

  let response;
  try {
    response = $http.send({
      url: relay.url.replace(/\/$/, "") + "/v1/wesi-telegram",
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Wesi-Request-Id": requestId,
        "X-Wesi-Timestamp": timestamp,
        "X-Wesi-Signature": signature,
      },
      body: raw,
      timeout: 20,
    });
  } catch (_) {
    return {ok: false, code: "TELEGRAM_RELAY_UNAVAILABLE"};
  }

  const data = response && response.json && typeof response.json === "object" ? response.json : {};
  if (!response || response.statusCode < 200 || response.statusCode >= 300 || data.ok !== true) {
    return {
      ok: false,
      code: String(data.code || "TELEGRAM_RELAY_BAD_RESPONSE"),
      description: String(data.description || ""),
    };
  }
  return {ok: true, result: data.result == null ? null : data.result};
}

function verifyInbound(e, cfg) {
  if (!e || !cfg || cfg.ready !== true) return false;
  const relay = relayConfig();
  if (!relay.ready || String(relay.sharedSecret || "").length < 32) return false;

  const telegramSecret = String(e.request.header.get("X-Telegram-Bot-Api-Secret-Token") || "");
  if (!telegramSecret || !$security.equal(telegramSecret, String(cfg.webhookSecret || ""))) return false;

  const requestId = String(e.request.header.get("X-Wesi-Request-Id") || "");
  const timestamp = String(e.request.header.get("X-Wesi-Timestamp") || "");
  const signature = String(e.request.header.get("X-Wesi-Signature") || "");
  const claimedUpdateId = String(e.request.header.get("X-Wesi-Telegram-Update-Id") || "");
  if (!/^wai_tg_in_[A-Za-z0-9_-]{8,120}$/.test(requestId)) return false;
  if (!/^[a-f0-9]{64}$/i.test(signature)) return false;

  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Math.floor(Date.now() / 1000) - ts) > MAX_SKEW_SECONDS) return false;

  const update = e.requestInfo().body || {};
  const updateId = String(update.update_id == null ? "" : update.update_id);
  if (!updateId || claimedUpdateId !== updateId) return false;

  const canonical = canonicalize(update);
  const expected = $security.hs256(requestId + "." + timestamp + "." + canonical, relay.sharedSecret);
  return $security.equal(signature, expected);
}

module.exports = {
  ALLOWED_METHODS,
  canonicalize,
  relayConfig,
  telegramApi,
  verifyInbound,
};
'''
write("server/pb_hooks/wesi_telegram_transport.js", TRANSPORT)


FOREIGN = r'''import crypto from 'node:crypto';
import {verifyMainRequest} from './auth.mjs';

const BOT_API = 'https://api.telegram.org';
const ALLOWED_METHODS = new Set([
  'sendMessage',
  'sendPhoto',
  'sendChatAction',
  'answerCallbackQuery',
  'deleteMessage',
  'deleteMessages',
  'setWebhook',
  'setMyName',
  'setMyDescription',
  'setMyShortDescription',
  'setMyCommands',
  'setChatMenuButton',
  'getWebhookInfo',
  'getMe',
  'getMyName',
  'getMyCommands',
  'getChatMenuButton',
]);

function envConfig(env = process.env) {
  return {
    sharedSecret: String(env.WESI_MAIN_SHARED_SECRET || ''),
    botToken: String(env.WESI_TELEGRAM_BOT_TOKEN || ''),
    webhookSecret: String(env.WESI_TELEGRAM_WEBHOOK_SECRET || ''),
    mainWebhookUrl: String(env.WESI_TELEGRAM_MAIN_WEBHOOK_URL || ''),
  };
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ''), 'utf8');
  const b = Buffer.from(String(right || ''), 'utf8');
  return a.length === b.length && a.length > 0 && crypto.timingSafeEqual(a, b);
}

export function canonicalize(value) {
  if (value === null || value === undefined) return 'null';
  if (Array.isArray(value)) return '[' + value.map(canonicalize).join(',') + ']';
  if (typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return '{' + keys.map((key) => JSON.stringify(key) + ':' + canonicalize(value[key])).join(',') + '}';
  }
  return JSON.stringify(value);
}

export function isAllowedTelegramMethod(method) {
  return ALLOWED_METHODS.has(String(method || ''));
}

export function telegramHealth(env = process.env) {
  const cfg = envConfig(env);
  const outbound = cfg.sharedSecret.length >= 32 && cfg.botToken.length >= 20;
  const inbound = cfg.sharedSecret.length >= 32 &&
    /^[A-Za-z0-9_-]{24,256}$/.test(cfg.webhookSecret) &&
    /^https:\/\//.test(cfg.mainWebhookUrl);
  return {ready: outbound && inbound, outbound, inbound};
}

async function telegramJson(method, payload, cfg, fetchImpl) {
  if (!isAllowedTelegramMethod(method)) {
    return {status: 403, body: {ok: false, code: 'TELEGRAM_METHOD_FORBIDDEN'}};
  }
  if (cfg.botToken.length < 20) {
    return {status: 503, body: {ok: false, code: 'TELEGRAM_RELAY_NOT_CONFIGURED'}};
  }
  let response;
  try {
    response = await fetchImpl(`${BOT_API}/bot${cfg.botToken}/${method}`, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify(payload || {}),
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    return {status: 502, body: {ok: false, code: 'TELEGRAM_UPSTREAM_UNAVAILABLE'}};
  }
  let data = {};
  try { data = await response.json(); } catch {}
  if (!response.ok || data?.ok !== true) {
    return {
      status: response.status === 429 ? 429 : 502,
      body: {
        ok: false,
        code: 'TELEGRAM_UPSTREAM_BAD_RESPONSE',
        description: String(data?.description || '').slice(0, 500),
      },
    };
  }
  return {status: 200, body: {ok: true, result: data.result ?? null}};
}

export async function handleTelegramApi(headers, rawBody, options = {}) {
  const env = options.env || process.env;
  const fetchImpl = options.fetchImpl || fetch;
  const cfg = envConfig(env);
  const auth = verifyMainRequest(headers, rawBody, cfg.sharedSecret, options.authOptions || {});
  if (!auth.ok) {
    return {status: auth.code === 'WAI_RELAY_NOT_CONFIGURED' ? 503 : 401, body: auth};
  }
  let request;
  try { request = JSON.parse(rawBody); }
  catch { return {status: 400, body: {ok: false, code: 'TELEGRAM_RELAY_BAD_JSON'}}; }
  if (String(request.requestId || '') !== auth.requestId) {
    return {status: 401, body: {ok: false, code: 'TELEGRAM_RELAY_AUTH_FAILED'}};
  }
  return telegramJson(String(request.method || ''), request.payload || {}, cfg, fetchImpl);
}

export async function handleTelegramWebhook(headers, rawBody, options = {}) {
  const env = options.env || process.env;
  const fetchImpl = options.fetchImpl || fetch;
  const cfg = envConfig(env);
  if (!telegramHealth(env).inbound) {
    return {status: 503, body: {ok: false, code: 'TELEGRAM_WEBHOOK_RELAY_NOT_CONFIGURED'}};
  }
  if (!safeEqual(headers['x-telegram-bot-api-secret-token'], cfg.webhookSecret)) {
    return {status: 401, body: {ok: false, code: 'TELEGRAM_WEBHOOK_UNAUTHORIZED'}};
  }

  let update;
  try { update = JSON.parse(rawBody); }
  catch { return {status: 400, body: {ok: false, code: 'TELEGRAM_WEBHOOK_BAD_JSON'}}; }
  const updateId = String(update?.update_id ?? '');
  if (!/^[0-9]{1,24}$/.test(updateId)) {
    return {status: 400, body: {ok: false, code: 'TELEGRAM_WEBHOOK_BAD_UPDATE'}};
  }

  const timestamp = String(Math.floor(Date.now() / 1000));
  const requestId = `wai_tg_in_${Date.now()}_${crypto.randomBytes(9).toString('base64url')}`;
  const canonical = canonicalize(update);
  const signature = crypto.createHmac('sha256', cfg.sharedSecret)
    .update(`${requestId}.${timestamp}.${canonical}`)
    .digest('hex');

  let response;
  try {
    response = await fetchImpl(cfg.mainWebhookUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-telegram-bot-api-secret-token': cfg.webhookSecret,
        'x-wesi-request-id': requestId,
        'x-wesi-timestamp': timestamp,
        'x-wesi-signature': signature,
        'x-wesi-telegram-update-id': updateId,
      },
      body: rawBody,
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    return {status: 502, body: {ok: false, code: 'TELEGRAM_MAIN_UNAVAILABLE'}};
  }
  if (!response.ok) {
    return {status: 502, body: {ok: false, code: 'TELEGRAM_MAIN_REJECTED', mainStatus: response.status}};
  }
  return {status: 200, body: {ok: true}};
}
'''
write("server/wesi-ai-relay/telegram.mjs", FOREIGN)


FOREIGN_TEST = r'''import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import {canonicalize, handleTelegramApi, handleTelegramWebhook, isAllowedTelegramMethod, telegramHealth} from './telegram.mjs';
import {resetReplayCache} from './auth.mjs';

const SECRET = 's'.repeat(64);
const BOT = '1234567890:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi';
const WEBHOOK = 'telegram_webhook_secret_abcdefghijklmnopqrstuvwxyz';
const ENV = {
  WESI_MAIN_SHARED_SECRET: SECRET,
  WESI_TELEGRAM_BOT_TOKEN: BOT,
  WESI_TELEGRAM_WEBHOOK_SECRET: WEBHOOK,
  WESI_TELEGRAM_MAIN_WEBHOOK_URL: 'https://api.wesi-inc.ru/api/wesi/telegram/webhook',
};

function signed(method, payload, nowMs = Date.now()) {
  const requestId = 'wai_tg_test_' + nowMs;
  const raw = JSON.stringify({requestId, method, payload});
  const timestamp = String(Math.floor(nowMs / 1000));
  const signature = crypto.createHmac('sha256', SECRET).update(`${requestId}.${timestamp}.${raw}`).digest('hex');
  return {raw, headers: {'x-wesi-request-id': requestId, 'x-wesi-timestamp': timestamp, 'x-wesi-signature': signature}};
}

test('Telegram relay has an explicit method allowlist', () => {
  assert.equal(isAllowedTelegramMethod('sendMessage'), true);
  assert.equal(isAllowedTelegramMethod('setWebhook'), true);
  assert.equal(isAllowedTelegramMethod('getWebhookInfo'), true);
  assert.equal(isAllowedTelegramMethod('getUpdates'), false);
  assert.equal(isAllowedTelegramMethod('../getMe'), false);
});

test('Canonical JSON is stable across object key order', () => {
  assert.equal(canonicalize({b: 2, a: {z: 1, y: [3, 2]}}), canonicalize({a: {y: [3, 2], z: 1}, b: 2}));
});

test('Health requires both outbound and inbound Telegram legs', () => {
  assert.deepEqual(telegramHealth(ENV), {ready: true, outbound: true, inbound: true});
  assert.equal(telegramHealth({...ENV, WESI_TELEGRAM_BOT_TOKEN: ''}).ready, false);
});

test('RU signed outbound request reaches Telegram only from foreign relay', async () => {
  resetReplayCache();
  const nowMs = 1_800_000_000_000;
  const req = signed('sendMessage', {chat_id: '1', text: 'ok'}, nowMs);
  let seenUrl = '';
  const result = await handleTelegramApi(req.headers, req.raw, {
    env: ENV,
    authOptions: {nowMs},
    fetchImpl: async (url) => {
      seenUrl = String(url);
      return {ok: true, status: 200, json: async () => ({ok: true, result: {message_id: 7}})};
    },
  });
  assert.equal(result.status, 200);
  assert.equal(result.body.result.message_id, 7);
  assert.match(seenUrl, /^https:\/\/api\.telegram\.org\/bot/);
});

test('Telegram webhook is signed and forwarded to Main Server', async () => {
  const raw = JSON.stringify({message: {text: '/brief'}, update_id: 77});
  let forwarded = null;
  const result = await handleTelegramWebhook(
    {'x-telegram-bot-api-secret-token': WEBHOOK},
    raw,
    {
      env: ENV,
      fetchImpl: async (url, init) => {
        forwarded = {url: String(url), init};
        return {ok: true, status: 200};
      },
    },
  );
  assert.equal(result.status, 200);
  assert.equal(forwarded.url, ENV.WESI_TELEGRAM_MAIN_WEBHOOK_URL);
  assert.match(forwarded.init.headers['x-wesi-request-id'], /^wai_tg_in_/);
  assert.equal(forwarded.init.headers['x-wesi-telegram-update-id'], '77');
  assert.match(forwarded.init.headers['x-wesi-signature'], /^[a-f0-9]{64}$/);
});
'''
write("server/wesi-ai-relay/telegram.test.mjs", FOREIGN_TEST)


# Main-server Telegram configuration no longer carries the Bot API token.
regex_once(
    "server/pb_hooks/wesi_telegram_store.js",
    r"function config\(\) \{.*?\n\}\n\nfunction createLinkCode",
    r'''function config() {
  let file = {};
  try {
    const raw = $os.readFile(__hooks + "/.wesi-telegram.json");
    const value = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
    file = JSON.parse(value || "{}");
  } catch (_) {}
  const webhookSecret = readEnv("WESI_TELEGRAM_WEBHOOK_SECRET") || String(file.webhookSecret || "").trim();
  const botUsername = readEnv("WESI_TELEGRAM_BOT_USERNAME") || String(file.botUsername || "WesiOSBot").trim();
  const publicBaseUrl = readEnv("WESI_PUBLIC_BASE_URL") || String(file.publicBaseUrl || "https://api.wesi-inc.ru").trim().replace(/\/$/, "");
  let relay = {ready: false, url: ""};
  try {
    const ai = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_lib.js");
    relay = ai.readRelayConfig();
  } catch (_) {}
  return {
    botToken: "",
    webhookSecret: webhookSecret,
    botUsername: botUsername.replace(/^@/, ""),
    publicBaseUrl: /^https:\/\//.test(publicBaseUrl) ? publicBaseUrl : "https://api.wesi-inc.ru",
    relayUrl: relay && relay.ready ? String(relay.url || "") : "",
    ready: !!(relay && relay.ready) && webhookSecret.length >= 24,
  };
}

function createLinkCode''',
)


def switch_api(rel, next_function):
    text = read(rel)
    store_line = 'const store = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_store.js");\n'
    transport_line = 'const transport = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_telegram_transport.js");\n'
    if transport_line not in text:
        if store_line not in text:
            raise SystemExit(f"store import marker missing: {rel}")
        text = text.replace(store_line, store_line + transport_line, 1)
    pattern = r"function telegramApi\(cfg, method, payload\) \{.*?\n\}\n\nfunction " + re.escape(next_function)
    replacement = 'function telegramApi(cfg, method, payload) {\n  return transport.telegramApi(cfg, method, payload);\n}\n\nfunction ' + next_function
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"telegramApi block not replaced in {rel}")
    write(rel, new)


switch_api("server/pb_hooks/wesi_telegram_gateway.js", "sendTyping")
switch_api("server/pb_hooks/wesi_telegram_experience.js", "inlineKeyboard")
switch_api("server/pb_hooks/wesi_telegram_interactions.js", "activePrivateLink")
switch_api("server/pb_hooks/wesi_telegram_morning.js", "timezoneOffset")


# Public RU webhook accepts only a request re-signed by the foreign relay.
replace_once(
    "server/pb_hooks/wesi_telegram.pb.js",
    'routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {\n',
    '''routerAdd("POST", "/api/wesi/telegram/webhook", (e) => {
  const store = require(`${__hooks}/wesi_telegram_store.js`);
  const transport = require(`${__hooks}/wesi_telegram_transport.js`);
  const cfg = store.config();
  if (!transport.verifyInbound(e, cfg)) {
    return e.json(401, {ok: false, code: "TELEGRAM_RELAY_REQUIRED"});
  }
''',
)


# Extend the already-running Wesi AI foreign process with Telegram routes.
replace_once(
    "server/wesi-ai-relay/server.mjs",
    "import {verifyMainRequest} from './auth.mjs';\n",
    "import {verifyMainRequest} from './auth.mjs';\nimport {handleTelegramApi, handleTelegramWebhook, telegramHealth} from './telegram.mjs';\n",
)
replace_once(
    "server/wesi-ai-relay/server.mjs",
    "      streaming: true,\n",
    "      streaming: true,\n      telegram: telegramHealth(),\n",
)
replace_once(
    "server/wesi-ai-relay/server.mjs",
    "  const isArtifact = req.method === 'POST' && req.url === '/v1/wesi-ai-artifact';\n  if (!isMain && !isStream && !isArtifact) return send(res, 404, {ok: false, code: 'NOT_FOUND'});\n",
    "  const isArtifact = req.method === 'POST' && req.url === '/v1/wesi-ai-artifact';\n  const isTelegramApi = req.method === 'POST' && req.url === '/v1/wesi-telegram';\n  const isTelegramWebhook = req.method === 'POST' && req.url === '/v1/wesi-telegram-webhook';\n  if (!isMain && !isStream && !isArtifact && !isTelegramApi && !isTelegramWebhook) return send(res, 404, {ok: false, code: 'NOT_FOUND'});\n",
)
replace_once(
    "server/wesi-ai-relay/server.mjs",
    "  const parsed = authenticate(req, raw);\n",
    "  if (isTelegramApi || isTelegramWebhook) {\n    const result = isTelegramApi\n      ? await handleTelegramApi(req.headers, raw)\n      : await handleTelegramWebhook(req.headers, raw);\n    return send(res, result.status || 502, result.body || {ok: false, code: 'TELEGRAM_RELAY_FAILED'});\n  }\n\n  const parsed = authenticate(req, raw);\n",
)


# HTTPS facade exposes exactly the two Telegram relay endpoints.
replace_once(
    "server/wesi-ai-relay/nginx-relay.conf",
    "    location / {\n        return 404;\n    }\n",
    '''    location = /v1/wesi-telegram {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_pass_request_headers on;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
        client_max_body_size 2m;
        add_header Cache-Control "no-store" always;
    }

    location = /v1/wesi-telegram-webhook {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_pass_request_headers on;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
        client_max_body_size 2m;
        add_header Cache-Control "no-store" always;
    }

    location / {
        return 404;
    }
''',
)


# Relay installer receives Telegram credentials in the same sealed file as Wesi AI.
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    "      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE=\"$decoded\" ;;\n",
    "      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE=\"$decoded\" ;;\n      WESI_TELEGRAM_BOT_TOKEN_B64) WESI_TELEGRAM_BOT_TOKEN=\"$decoded\" ;;\n      WESI_TELEGRAM_WEBHOOK_SECRET_B64) WESI_TELEGRAM_WEBHOOK_SECRET=\"$decoded\" ;;\n      WESI_TELEGRAM_MAIN_WEBHOOK_URL_B64) WESI_TELEGRAM_MAIN_WEBHOOK_URL=\"$decoded\" ;;\n",
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    "  export WESI_NIRVANA_TTS_VOICE=\"${WESI_NIRVANA_TTS_VOICE:-Sulafat}\"\n",
    "  export WESI_NIRVANA_TTS_VOICE=\"${WESI_NIRVANA_TTS_VOICE:-Sulafat}\"\n  export WESI_TELEGRAM_BOT_TOKEN=\"${WESI_TELEGRAM_BOT_TOKEN:-}\"\n  export WESI_TELEGRAM_WEBHOOK_SECRET=\"${WESI_TELEGRAM_WEBHOOK_SECRET:-}\"\n  export WESI_TELEGRAM_MAIN_WEBHOOK_URL=\"${WESI_TELEGRAM_MAIN_WEBHOOK_URL:-}\"\n",
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    "  [ -n \"${GEMINI_API_KEY:-}\" ] || missing+=(\"GEMINI_API_KEY\")\n",
    "  [ -n \"${GEMINI_API_KEY:-}\" ] || missing+=(\"GEMINI_API_KEY\")\n  [ -n \"${WESI_TELEGRAM_BOT_TOKEN:-}\" ] || missing+=(\"WESI_TELEGRAM_BOT_TOKEN\")\n  [ -n \"${WESI_TELEGRAM_WEBHOOK_SECRET:-}\" ] || missing+=(\"WESI_TELEGRAM_WEBHOOK_SECRET\")\n  [ -n \"${WESI_TELEGRAM_MAIN_WEBHOOK_URL:-}\" ] || missing+=(\"WESI_TELEGRAM_MAIN_WEBHOOK_URL\")\n",
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    "  [ \"${#WESI_MAIN_SHARED_SECRET}\" -ge 32 ] || fail \"WESI_MAIN_SHARED_SECRET короче 32 символов\"\n",
    "  [ \"${#WESI_MAIN_SHARED_SECRET}\" -ge 32 ] || fail \"WESI_MAIN_SHARED_SECRET короче 32 символов\"\n  [ \"${#WESI_TELEGRAM_BOT_TOKEN}\" -ge 20 ] || fail \"WESI_TELEGRAM_BOT_TOKEN некорректен\"\n  [[ \"$WESI_TELEGRAM_WEBHOOK_SECRET\" =~ ^[A-Za-z0-9_-]{24,256}$ ]] || fail \"WESI_TELEGRAM_WEBHOOK_SECRET некорректен\"\n  [[ \"$WESI_TELEGRAM_MAIN_WEBHOOK_URL\" =~ ^https:// ]] || fail \"WESI_TELEGRAM_MAIN_WEBHOOK_URL должен быть HTTPS\"\n",
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    "WESI_ENABLE_PAID_MEDIA=${WESI_ENABLE_PAID_MEDIA:-false}\nENV\n",
    "WESI_ENABLE_PAID_MEDIA=${WESI_ENABLE_PAID_MEDIA:-false}\nWESI_TELEGRAM_BOT_TOKEN=$WESI_TELEGRAM_BOT_TOKEN\nWESI_TELEGRAM_WEBHOOK_SECRET=$WESI_TELEGRAM_WEBHOOK_SECRET\nWESI_TELEGRAM_MAIN_WEBHOOK_URL=$WESI_TELEGRAM_MAIN_WEBHOOK_URL\nENV\n",
)


# Wesi AI E2E deploy now provisions Telegram on the same foreign host.
ai_workflow = ".github/workflows/deploy-wesi-ai.yml"
replace_once(
    ai_workflow,
    "    paths:\n      - '.github/wesi-ai-router-deploy.trigger'\n",
    "    paths:\n      - '.github/wesi-ai-router-deploy.trigger'\n      - 'server/wesi-ai-relay/**'\n      - '.github/workflows/deploy-wesi-ai.yml'\n",
)
replace_once(
    ai_workflow,
    "      MAIN_USER: ${{ secrets.WESI_SERVER_USER }}\n",
    "      MAIN_USER: ${{ secrets.WESI_SERVER_USER }}\n      MAIN_PUBLIC_BASE_URL: ${{ vars.WESI_PUBLIC_BASE_URL || 'https://api.wesi-inc.ru' }}\n",
)
replace_once(
    ai_workflow,
    "          NIRVANA_VOICE: ${{ secrets.WESI_NIRVANA_TTS_VOICE }}\n",
    "          NIRVANA_VOICE: ${{ secrets.WESI_NIRVANA_TTS_VOICE }}\n          BOT_TOKEN_PRIMARY: ${{ secrets.WESI_TELEGRAM_BOT_TOKEN }}\n          BOT_TOKEN_LEGACY: ${{ secrets.TELEGRAM_BOT_TOKEN }}\n          TELEGRAM_WEBHOOK_SECRET_INPUT: ${{ secrets.WESI_TELEGRAM_WEBHOOK_SECRET }}\n",
)
replace_once(
    ai_workflow,
    "          set -euo pipefail\n          python3 - <<'PY'\n          import base64, os\n          values = {\n",
    "          set -euo pipefail\n          BOT_TOKEN=\"${BOT_TOKEN_PRIMARY:-${BOT_TOKEN_LEGACY:-}}\"\n          [ -n \"$BOT_TOKEN\" ] || { echo '::error::Telegram bot token is missing'; exit 1; }\n          WEBHOOK_SECRET=\"${TELEGRAM_WEBHOOK_SECRET_INPUT:-}\"\n          if [ -z \"$WEBHOOK_SECRET\" ]; then\n            WEBHOOK_SECRET=\"$(python3 -c 'import hashlib,sys; print(hashlib.sha256((\"wesios-telegram-webhook-v1:\"+sys.argv[1]).encode()).hexdigest())' \"$BOT_TOKEN\")\"\n          fi\n          [[ \"$WEBHOOK_SECRET\" =~ ^[A-Za-z0-9_-]{24,256}$ ]] || { echo '::error::Bad Telegram webhook secret'; exit 1; }\n          echo \"::add-mask::$BOT_TOKEN\"\n          echo \"::add-mask::$WEBHOOK_SECRET\"\n          echo \"WESI_TELEGRAM_WEBHOOK_SECRET_VALUE=$WEBHOOK_SECRET\" >> \"$GITHUB_ENV\"\n          export BOT_TOKEN WEBHOOK_SECRET\n          python3 - <<'PY'\n          import base64, os\n          values = {\n",
)
replace_once(
    ai_workflow,
    "              'GEMINI_API_KEY_B64': os.environ['GEMINI_KEY'],\n          }\n",
    "              'GEMINI_API_KEY_B64': os.environ['GEMINI_KEY'],\n              'WESI_TELEGRAM_BOT_TOKEN_B64': os.environ['BOT_TOKEN'],\n              'WESI_TELEGRAM_WEBHOOK_SECRET_B64': os.environ['WEBHOOK_SECRET'],\n              'WESI_TELEGRAM_MAIN_WEBHOOK_URL_B64': os.environ['MAIN_PUBLIC_BASE_URL'].rstrip('/') + '/api/wesi/telegram/webhook',\n          }\n",
)
replace_once(
    ai_workflow,
    "          assert data.get('routing') == ['fast','pro','ultra'], data\n",
    "          assert data.get('routing') == ['fast','pro','ultra'], data\n          assert (data.get('telegram') or {}).get('ready') is True, data\n",
)

configure_step = r'''      - name: Configure Telegram through Foreign Relay
        env:
          TELEGRAM_WEBHOOK_SECRET: ${{ env.WESI_TELEGRAM_WEBHOOK_SECRET_VALUE }}
        run: |
          set -euo pipefail
          python3 - <<'PY'
          import hashlib, hmac, json, os, time, urllib.request
          base='https://' + os.environ['PUBLIC_HOST']
          secret=os.environ['WESI_SHARED_SECRET'].encode()
          webhook_secret=os.environ['TELEGRAM_WEBHOOK_SECRET']
          expected_webhook=base + '/v1/wesi-telegram-webhook'

          def call(method, payload=None):
              rid='wai_tg_deploy_' + str(time.time_ns())
              body={'requestId': rid, 'method': method, 'payload': payload or {}}
              raw=json.dumps(body,separators=(',',':'),ensure_ascii=False).encode()
              ts=str(int(time.time()))
              sig=hmac.new(secret, rid.encode()+b'.'+ts.encode()+b'.'+raw, hashlib.sha256).hexdigest()
              req=urllib.request.Request(base+'/v1/wesi-telegram', data=raw, method='POST', headers={
                  'Content-Type':'application/json', 'X-Wesi-Request-Id':rid,
                  'X-Wesi-Timestamp':ts, 'X-Wesi-Signature':sig,
              })
              with urllib.request.urlopen(req, timeout=30) as response:
                  data=json.load(response)
              assert data.get('ok') is True, (method, data)
              return data.get('result')

          call('setWebhook', {
              'url': expected_webhook,
              'secret_token': webhook_secret,
              'allowed_updates': ['message','callback_query'],
              'drop_pending_updates': False,
          })
          call('setMyName', {'name':'WesiOS: BUSINESS OPERATING SYSTEM'})
          call('setMyDescription', {'description':'WesiOS — операционная система бизнеса в Telegram: сводка, деньги, риски, задачи, организации и серверные уведомления.'})
          call('setMyShortDescription', {'short_description':'WesiOS — управление бизнесом и важные сигналы прямо в Telegram.'})
          call('setMyCommands', {'commands':[
              {'command':'brief','description':'📊 Главная сводка'},
              {'command':'cash','description':'💰 Деньги и текущий баланс'},
              {'command':'risk','description':'⚠️ Риски и кассовый runway'},
              {'command':'today','description':'✅ Задачи на сегодня'},
              {'command':'overdue','description':'⏰ Просроченные задачи'},
              {'command':'org','description':'🏢 Выбрать организацию'},
              {'command':'test','description':'🔔 Проверить Telegram-уведомления'},
              {'command':'help','description':'🧭 Все возможности'},
          ]})
          call('setChatMenuButton', {'menu_button':{'type':'commands'}})
          info=call('getWebhookInfo') or {}
          assert info.get('url') == expected_webhook, info
          name=call('getMyName') or {}
          assert name.get('name') == 'WesiOS: BUSINESS OPERATING SYSTEM', name
          commands=call('getMyCommands') or []
          assert [x.get('command') for x in commands] == ['brief','cash','risk','today','overdue','org','test','help'], commands
          print('WESI_TELEGRAM_FOREIGN_RELAY_CONFIGURED', expected_webhook)
          PY

'''
replace_once(ai_workflow, "      - name: Prepare Main Wesi Server SSH\n", configure_step + "      - name: Prepare Main Wesi Server SSH\n")


# Telegram deployment installs only Main Server hooks. Bot API setup moved to foreign deploy.
tg_workflow = ".github/workflows/deploy-wesi-telegram.yml"
replace_once(
    tg_workflow,
    "            server/pb_hooks/wesi_telegram_store.js \\\n            server/pb_hooks/wesi_telegram_gateway.js \\\n",
    "            server/pb_hooks/wesi_telegram_store.js \\\n            server/pb_hooks/wesi_telegram_transport.js \\\n            server/pb_hooks/wesi_telegram_gateway.js \\\n",
)
replace_once(
    tg_workflow,
    "            server/pb_hooks/wesi_telegram_interactions.js \\\n            server/pb_hooks/wesi_telegram.pb.js \\\n",
    "            server/pb_hooks/wesi_telegram_interactions.js \\\n            server/pb_hooks/wesi_telegram_morning_photos.js \\\n            server/pb_hooks/wesi_telegram_morning.js \\\n            server/pb_hooks/wesi_telegram.pb.js \\\n",
)
replace_once(
    tg_workflow,
    "                  'botToken': os.environ['BOT_TOKEN'],\n",
    "",
)
replace_once(tg_workflow, "          echo \"BOT_TOKEN=$BOT_TOKEN\" >> \"$GITHUB_ENV\"\n", "")
replace_once(
    tg_workflow,
    "            server/pb_hooks/wesi_telegram_store.js \\\n            server/pb_hooks/wesi_telegram_gateway.js \\\n",
    "            server/pb_hooks/wesi_telegram_store.js \\\n            server/pb_hooks/wesi_telegram_transport.js \\\n            server/pb_hooks/wesi_telegram_gateway.js \\\n",
)
replace_once(
    tg_workflow,
    "            server/pb_hooks/wesi_telegram_interactions.js \\\n            server/pb_hooks/wesi_telegram.pb.js \\\n",
    "            server/pb_hooks/wesi_telegram_interactions.js \\\n            server/pb_hooks/wesi_telegram_morning_photos.js \\\n            server/pb_hooks/wesi_telegram_morning.js \\\n            server/pb_hooks/wesi_telegram.pb.js \\\n",
)
replace_once(
    tg_workflow,
    "          atomic_install \"$REMOTE/wesi_telegram_store.js\" \"$HOOK_DIR/wesi_telegram_store.js\" 0644\n",
    "          atomic_install \"$REMOTE/wesi_telegram_store.js\" \"$HOOK_DIR/wesi_telegram_store.js\" 0644\n          atomic_install \"$REMOTE/wesi_telegram_transport.js\" \"$HOOK_DIR/wesi_telegram_transport.js\" 0644\n",
)
replace_once(
    tg_workflow,
    "          atomic_install \"$REMOTE/wesi_telegram_interactions.js\" \"$HOOK_DIR/wesi_telegram_interactions.js\" 0644\n",
    "          atomic_install \"$REMOTE/wesi_telegram_interactions.js\" \"$HOOK_DIR/wesi_telegram_interactions.js\" 0644\n          atomic_install \"$REMOTE/wesi_telegram_morning_photos.js\" \"$HOOK_DIR/wesi_telegram_morning_photos.js\" 0644\n          atomic_install \"$REMOTE/wesi_telegram_morning.js\" \"$HOOK_DIR/wesi_telegram_morning.js\" 0644\n",
)
replace_once(
    tg_workflow,
    "          cmp -s \"$REMOTE/wesi_telegram_experience.js\" \"$HOOK_DIR/wesi_telegram_experience.js\"\n",
    "          cmp -s \"$REMOTE/wesi_telegram_experience.js\" \"$HOOK_DIR/wesi_telegram_experience.js\"\n          cmp -s \"$REMOTE/wesi_telegram_transport.js\" \"$HOOK_DIR/wesi_telegram_transport.js\"\n          cmp -s \"$REMOTE/wesi_telegram_morning.js\" \"$HOOK_DIR/wesi_telegram_morning.js\"\n",
)
regex_once(
    tg_workflow,
    r"      - name: Configure Telegram profile menu and webhook\n        id: telegram\n        run: \|\n.*?\n      - name: Verify public Telegram routes and visuals",
    r'''      - name: Verify foreign-only Telegram transport policy
        id: telegram
        run: |
          set -euo pipefail
          if grep -R -n -F 'api.telegram.org' server/pb_hooks/wesi_telegram*.js; then
            echo '::error::Russian Main Server must never call Telegram Bot API directly.'
            exit 1
          fi
          grep -q '/v1/wesi-telegram' server/pb_hooks/wesi_telegram_transport.js
          grep -q 'verifyInbound' server/pb_hooks/wesi_telegram.pb.js
          grep -q 'TELEGRAM_RELAY_REQUIRED' server/pb_hooks/wesi_telegram.pb.js
          echo WESI_TELEGRAM_MAIN_USES_FOREIGN_RELAY_ONLY

      - name: Verify public Telegram routes and visuals''',
)


# Gate checks both legs and makes direct RU Bot API regressions impossible.
gate = ".github/workflows/telegram-gate.yml"
replace_once(
    gate,
    "      - '.github/workflows/deploy-wesi-telegram.yml'\n",
    "      - '.github/workflows/deploy-wesi-telegram.yml'\n      - '.github/workflows/deploy-wesi-ai.yml'\n      - 'server/wesi-ai-relay/telegram*.mjs'\n",
)
replace_once(
    gate,
    "            server/pb_hooks/wesi_telegram_store.js \\\n",
    "            server/pb_hooks/wesi_telegram_store.js \\\n            server/pb_hooks/wesi_telegram_transport.js \\\n",
)
replace_once(
    gate,
    "            server/pb_hooks/wesi_ai_task_tools.js; do\n",
    "            server/pb_hooks/wesi_ai_task_tools.js \\\n            server/wesi-ai-relay/telegram.mjs; do\n",
)
replace_once(
    gate,
    "          node server/pb_hooks/wesi_telegram_morning_test.mjs\n",
    "          node server/pb_hooks/wesi_telegram_morning_test.mjs\n          node --test server/wesi-ai-relay/telegram.test.mjs\n",
)
replace_once(
    gate,
    "      - name: Reject legacy Vercel dependencies\n",
    '''      - name: Enforce foreign-only Telegram network path
        shell: bash
        run: |
          set -euo pipefail
          if grep -R -n -F 'api.telegram.org' server/pb_hooks/wesi_telegram*.js .github/workflows/deploy-wesi-telegram.yml; then
            echo '::error::Only the foreign relay may contact api.telegram.org.'
            exit 1
          fi
          count="$(grep -R -l -F 'api.telegram.org' server/wesi-ai-relay/telegram.mjs | wc -l)"
          test "$count" = "1"
          grep -q '/v1/wesi-telegram-webhook' server/wesi-ai-relay/nginx-relay.conf
          grep -q 'TELEGRAM_RELAY_REQUIRED' server/pb_hooks/wesi_telegram.pb.js

      - name: Reject legacy Vercel dependencies
''',
)


# Deployment workflow validation needs the new transport and morning hooks in its first file list.
# Exact duplication is intentionally rejected above by replace_once if upstream layout changes.

# Remove this one-shot migrator and its workflow from the resulting branch commit.
path("scripts/apply_telegram_foreign_relay_migration.py").unlink(missing_ok=True)
path(".github/workflows/apply-telegram-foreign-relay-once.yml").unlink(missing_ok=True)

print("TELEGRAM_FOREIGN_RELAY_MIGRATION_APPLIED")
