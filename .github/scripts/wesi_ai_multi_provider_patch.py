from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path, old, new):
    text = read(path)
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected patch anchor missing: {path}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


# 1) Relay deployment must install every runtime module and keep optional
# provider credentials only on the foreign Relay.
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    'ENV_FILE="/etc/wesi-ai-relay.env"\nSERVICE=',
    'ENV_FILE="/etc/wesi-ai-relay.env"\nPROVIDER_ENV_FILE="/etc/wesi-ai-providers.env"\nSERVICE=',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    '      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE="$decoded" ;;\n      *) fail',
    '      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE="$decoded" ;;\n'
    '      GROQ_API_KEY_B64) GROQ_API_KEY="$decoded" ;;\n'
    '      MISTRAL_API_KEY_B64) MISTRAL_API_KEY="$decoded" ;;\n'
    '      OPENROUTER_API_KEY_B64) OPENROUTER_API_KEY="$decoded" ;;\n'
    '      *) fail',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    '  if contains_newline "$GEMINI_API_KEY"; then fail "Gemini key содержит перевод строки"; fi\n  return 0',
    '  if contains_newline "$GEMINI_API_KEY"; then fail "Gemini key содержит перевод строки"; fi\n'
    '  local optional\n'
    '  for optional in GROQ_API_KEY MISTRAL_API_KEY OPENROUTER_API_KEY; do\n'
    '    if [ -n "${!optional:-}" ] && contains_newline "${!optional}"; then fail "$optional содержит перевод строки"; fi\n'
    '  done\n'
    '  return 0',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    '  for file in server.mjs auth.mjs google.mjs attachment-preprocessor.mjs google-media.mjs google-artifact.mjs media-cache.mjs package.json; do',
    '  for file in server.mjs auth.mjs google.mjs text-stream.mjs attachment-preprocessor.mjs staged-upload.mjs google-media.mjs google-artifact.mjs media-cache.mjs package.json; do',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    'WESI_ENABLE_PAID_MEDIA=${WESI_ENABLE_PAID_MEDIA:-false}\nENV\n\n  id -u wesi-relay',
    'WESI_ENABLE_PAID_MEDIA=${WESI_ENABLE_PAID_MEDIA:-false}\nENV\n\n'
    '  : >"$PROVIDER_ENV_FILE"\n'
    '  [ -n "${GROQ_API_KEY:-}" ] && printf "GROQ_API_KEY=%s\\n" "$GROQ_API_KEY" >>"$PROVIDER_ENV_FILE"\n'
    '  [ -n "${MISTRAL_API_KEY:-}" ] && printf "MISTRAL_API_KEY=%s\\n" "$MISTRAL_API_KEY" >>"$PROVIDER_ENV_FILE"\n'
    '  [ -n "${OPENROUTER_API_KEY:-}" ] && printf "OPENROUTER_API_KEY=%s\\n" "$OPENROUTER_API_KEY" >>"$PROVIDER_ENV_FILE"\n\n'
    '  id -u wesi-relay',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    '  chown root:wesi-relay "$ENV_FILE"\n  chmod 640 "$ENV_FILE"',
    '  chown root:wesi-relay "$ENV_FILE" "$PROVIDER_ENV_FILE"\n  chmod 640 "$ENV_FILE" "$PROVIDER_ENV_FILE"',
)
replace_once(
    "server/wesi-ai-relay/deploy-relay.sh",
    '  rm -f "$SERVICE" "$ENV_FILE"',
    '  rm -f "$SERVICE" "$ENV_FILE" "$PROVIDER_ENV_FILE"',
)

# 2) Current Relay VPS runs an nginx generation where HTTP/2 is a listen flag.
nginx = read("server/wesi-ai-relay/nginx-relay.conf")
nginx = nginx.replace("    listen 443 ssl;\n    listen [::]:443 ssl;\n    http2 on;", "    listen 443 ssl http2;\n    listen [::]:443 ssl http2;")
write("server/wesi-ai-relay/nginx-relay.conf", nginx)

# 3) Both production deploy workflows seal optional provider keys for Relay only.
for wf in [".github/workflows/deploy-wesi-ai.yml", ".github/workflows/deploy-wesi-ai-streaming.yml"]:
    text = read(wf)
    anchor = "          GEMINI_KEY: ${{ secrets.GEMINI_API_KEY }}\n          ZANE_VOICE: ${{ secrets.WESI_ZANE_TTS_VOICE }}"
    replacement = (
        "          GEMINI_KEY: ${{ secrets.GEMINI_API_KEY }}\n"
        "          GROQ_KEY: ${{ secrets.GROQ_API_KEY }}\n"
        "          MISTRAL_KEY: ${{ secrets.MISTRAL_API_KEY }}\n"
        "          OPENROUTER_KEY: ${{ secrets.OPENROUTER_API_KEY }}\n"
        "          ZANE_VOICE: ${{ secrets.WESI_ZANE_TTS_VOICE }}"
    )
    if replacement not in text:
        if anchor not in text:
            raise SystemExit(f"workflow env anchor missing: {wf}")
        text = text.replace(anchor, replacement, 1)
    if wf.endswith("deploy-wesi-ai.yml"):
        anchor2 = "          if os.environ.get('NIRVANA_VOICE'): values['WESI_NIRVANA_TTS_VOICE_B64'] = os.environ['NIRVANA_VOICE']\n"
        repl2 = anchor2 + (
            "          if os.environ.get('GROQ_KEY'): values['GROQ_API_KEY_B64'] = os.environ['GROQ_KEY']\n"
            "          if os.environ.get('MISTRAL_KEY'): values['MISTRAL_API_KEY_B64'] = os.environ['MISTRAL_KEY']\n"
            "          if os.environ.get('OPENROUTER_KEY'): values['OPENROUTER_API_KEY_B64'] = os.environ['OPENROUTER_KEY']\n"
        )
    else:
        anchor2 = "          if os.environ.get('NIRVANA_VOICE'):\n              relay['WESI_NIRVANA_TTS_VOICE_B64'] = os.environ['NIRVANA_VOICE']\n"
        repl2 = anchor2 + (
            "          if os.environ.get('GROQ_KEY'):\n              relay['GROQ_API_KEY_B64'] = os.environ['GROQ_KEY']\n"
            "          if os.environ.get('MISTRAL_KEY'):\n              relay['MISTRAL_API_KEY_B64'] = os.environ['MISTRAL_KEY']\n"
            "          if os.environ.get('OPENROUTER_KEY'):\n              relay['OPENROUTER_API_KEY_B64'] = os.environ['OPENROUTER_KEY']\n"
        )
    if repl2 not in text:
        if anchor2 not in text:
            raise SystemExit(f"workflow python anchor missing: {wf}")
        text = text.replace(anchor2, repl2, 1)
    write(wf, text)

# 4) Multi-provider orchestration. Fast stays latency-first. Pro consults two
# independent advisors (OpenRouter fills a missing seat). Maximum consults all
# three configured non-Gemini providers. Gemini is the sole finalizer.
google_path = "server/wesi-ai-relay/google.mjs"
google = read(google_path)
if "[WESI_AI_ENSEMBLE_FINALIZER]" not in google:
    google = google.replace(
        "async function callOpenAiCompatible({url, model, apiKey, input, headers = {}}) {",
        "function boundedSignal(parent, timeoutMs) {\n"
        "  const timeout = AbortSignal.timeout(Math.max(1000, Math.min(Number(timeoutMs || 120000), 180000)));\n"
        "  if (!parent) return timeout;\n"
        "  return typeof AbortSignal.any === 'function' ? AbortSignal.any([parent, timeout]) : parent;\n"
        "}\n\n"
        "async function callOpenAiCompatible({url, model, apiKey, input, headers = {}, timeoutMs = 120000, signal = null}) {",
        1,
    )
    google = google.replace("    signal: AbortSignal.timeout(120000),", "    signal: boundedSignal(signal, timeoutMs),", 1)
    google = google.replace("export async function callGoogleText(model, input, apiKey) {", "export async function callGoogleText(model, input, apiKey, options = {}) {", 1)
    google = google.replace("      signal: AbortSignal.timeout(180000),", "      signal: boundedSignal(options.signal || null, options.timeoutMs || 180000),", 1)
    tail_start = google.index("async function callCandidate(")
    google = google[:tail_start] + r'''async function callCandidate(candidate, input, googleKey, secrets, options = {}) {
  const timeoutMs = candidate.timeoutMs || options.timeoutMs || 30000;
  const signal = options.signal || null;
  if (candidate.provider === 'google') {
    return callGoogleText(candidate.model, input, googleKey, {timeoutMs, signal});
  }
  if (hasAttachments(input)) return {ok: false, status: 400, code: 'WAI_PROVIDER_NOT_MULTIMODAL'};
  if (candidate.provider === 'groq') {
    return callOpenAiCompatible({
      url: 'https://api.groq.com/openai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.GROQ_API_KEY,
      input,
      timeoutMs,
      signal,
    });
  }
  if (candidate.provider === 'mistral') {
    return callOpenAiCompatible({
      url: 'https://api.mistral.ai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.MISTRAL_API_KEY,
      input,
      timeoutMs,
      signal,
    });
  }
  if (candidate.provider === 'openrouter') {
    return callOpenAiCompatible({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.OPENROUTER_API_KEY,
      input,
      headers: {'HTTP-Referer': 'https://wesi-inc.ru', 'X-Title': 'Wesi AI'},
      timeoutMs,
      signal,
    });
  }
  return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
}

async function safeCandidate(candidate, input, googleKey, secrets, options = {}) {
  try {
    return await callCandidate(candidate, input, googleKey, secrets, options);
  } catch (error) {
    if (options.signal?.aborted) throw error;
    return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE'};
  }
}

async function firstAvailable(candidates, input, googleKey, secrets, options = {}) {
  let last = {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  for (const candidate of candidates) {
    const result = await safeCandidate(candidate, input, googleKey, secrets, options);
    if (result.ok) return {...result, provider: candidate.provider, model: candidate.model};
    last = result;
  }
  return last;
}

function clipAdvisor(text, limit) {
  const value = String(text || '').trim();
  return value.length <= limit ? value : `${value.slice(0, limit)}\n[truncated]`;
}

function advisorInput(input, tier) {
  return {
    system: `${String(input.system || '')}\n\n[WESI_AI_ADVISOR_ROLE]\nТы вспомогательный аналитик Wesi AI ${tier === 'ultra' ? 'Maximum' : 'Pro'}. Дай независимый разбор фактов, рисков, вариантов и ошибок. Не выдавай финальный ответ от лица Зейна/Нирваны. Не выводи JSON wesiTool и не утверждай, что действие WesiOS выполнено: инструменты может выбрать только финализатор.`,
    history: Array.isArray(input.history) ? input.history : [],
    message: String(input.message || ''),
  };
}

function finalizerInput(tier, input, advisors) {
  const perAdvisor = tier === 'ultra' ? 12000 : 9000;
  const notes = advisors
    .map((item, index) => `Аналитик ${index + 1}:\n${clipAdvisor(item.answer, perAdvisor)}`)
    .join('\n\n');
  return {
    system: `${String(input.system || '')}\n\n[WESI_AI_ENSEMBLE_FINALIZER]\nТы единственный финализатор Wesi AI ${tier === 'ultra' ? 'Maximum' : 'Pro'}. Сопоставь независимые аналитические заметки, исправь противоречия и сформируй один окончательный ответ в заданной персоне. Не упоминай внутренние модели, провайдеров, маршрутизацию или черновики. Если в исходном system есть WESI_AI_TOOL_PROTOCOL, только ты можешь решить, нужен ли один wesiTool-вызов; вспомогательные заметки никогда не являются подтверждением выполнения действия.`,
    history: Array.isArray(input.history) ? input.history : [],
    message: `Исходный запрос пользователя:\n${String(input.message || '')}\n\n[WESI_AI_ADVISOR_NOTES]\n${notes}`,
  };
}

export async function prepareWesiEnsemble(tier, input, googleKey, options = {}) {
  const normalized = String(tier || '').toLowerCase();
  if (normalized !== 'pro' && normalized !== 'ultra') {
    return {ok: false, code: 'WAI_ENSEMBLE_TIER_INVALID'};
  }
  const secrets = options.secrets || providerSecrets();
  const signal = options.signal || null;
  const advisory = advisorInput(input, normalized);
  const primary = normalized === 'pro'
    ? [
        {provider: 'groq', model: 'openai/gpt-oss-120b', timeoutMs: 28000},
        {provider: 'mistral', model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest', timeoutMs: 28000},
      ]
    : [
        {provider: 'groq', model: 'openai/gpt-oss-120b', timeoutMs: 32000},
        {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest', timeoutMs: 32000},
        {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 32000},
      ];
  const results = await Promise.all(primary.map(async (candidate) => {
    const result = await safeCandidate(candidate, advisory, googleKey, secrets, {signal});
    return result.ok ? {...result, provider: candidate.provider, model: candidate.model} : result;
  }));
  let advisors = results.filter((item) => item.ok);

  // Pro prefers two strong independent opinions; OpenRouter fills a missing
  // seat but does not add latency when both primary advisors are healthy.
  if (normalized === 'pro' && advisors.length < 2 && secrets.OPENROUTER_API_KEY) {
    const fallbackCandidate = {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 24000};
    const fallback = await safeCandidate(fallbackCandidate, advisory, googleKey, secrets, {signal});
    if (fallback.ok) advisors = advisors.concat({...fallback, provider: fallbackCandidate.provider, model: fallbackCandidate.model});
  }

  if (!advisors.length) return {ok: false, code: 'WAI_ENSEMBLE_ADVISORS_UNAVAILABLE'};
  return {
    ok: true,
    advisorCount: advisors.length,
    finalizerInput: finalizerInput(normalized, input, advisors),
    fallback: advisors[0],
  };
}

async function callEnsemble(tier, input, googleKey, secrets, options = {}) {
  const prepared = await prepareWesiEnsemble(tier, input, googleKey, {secrets, signal: options.signal || null});
  if (!prepared.ok) {
    return callGoogleText('gemini-3.5-flash', input, googleKey, {timeoutMs: 55000, signal: options.signal || null});
  }
  let final;
  try {
    final = await callGoogleText('gemini-3.5-flash', prepared.finalizerInput, googleKey, {
      timeoutMs: tier === 'ultra' ? 58000 : 52000,
      signal: options.signal || null,
    });
  } catch (error) {
    if (options.signal?.aborted) throw error;
    final = {ok: false, status: 502, code: 'WAI_FINALIZER_UNAVAILABLE'};
  }
  if (final.ok) {
    return {...final, provider: tier === 'ultra' ? 'wesi-maximum' : 'wesi-pro', model: 'ensemble'};
  }
  // Availability fallback only: advisor notes are never treated as verified
  // tool results. This keeps chat usable during a temporary Gemini outage.
  return {...prepared.fallback, provider: 'wesi-ensemble-fallback', model: 'advisor'};
}

export async function callTextRoute(route, input, googleKey, options = {}) {
  const direct = parseGoogleRoute(route);
  if (direct) return callGoogleText(direct.model, input, googleKey, options);

  const tier = parseWesiRoute(route);
  if (!tier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  const secrets = options.secrets || providerSecrets();

  if (hasAttachments(input)) {
    const model = tier === 'fast' ? 'gemini-3.5-flash-lite' : 'gemini-3.5-flash';
    const result = await callGoogleText(model, input, googleKey, {timeoutMs: 60000, signal: options.signal || null});
    return result.ok ? {...result, provider: 'google', model} : result;
  }

  if (tier === 'fast') {
    return firstAvailable([
      {provider: 'google', model: 'gemini-3.5-flash-lite', timeoutMs: 22000},
      {provider: 'groq', model: 'llama-3.1-8b-instant', timeoutMs: 18000},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_FAST_MODEL || 'mistral-small-latest', timeoutMs: 18000},
      {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 18000},
    ], input, googleKey, secrets, {signal: options.signal || null});
  }
  if (tier === 'pro') return callEnsemble('pro', input, googleKey, secrets, options);
  return callEnsemble('ultra', input, googleKey, secrets, options);
}
'''
    write(google_path, google)

# 5) Streaming keeps true final-answer streaming while the advisor stage stays
# hidden. Pro/Maximum must not bypass the ensemble after streaming is restored.
stream_path = "server/wesi-ai-relay/text-stream.mjs"
stream = read(stream_path)
if "async function streamEnsemble(" not in stream:
    stream = stream.replace(
        "import {callGoogleText, parseGoogleRoute} from './google.mjs';",
        "import {callGoogleText, parseGoogleRoute, prepareWesiEnsemble} from './google.mjs';",
        1,
    )
    start = stream.index("async function callUltraStream(")
    end = stream.index("export async function streamTextRoute(")
    helper = r'''async function streamEnsemble(tier, input, googleKey, secrets, signal, onDelta) {
  const prepared = await prepareWesiEnsemble(tier, input, googleKey, {secrets, signal});
  if (!prepared.ok) {
    return streamGoogle('gemini-3.5-flash', input, googleKey, signal, onDelta);
  }
  const final = await streamGoogle('gemini-3.5-flash', prepared.finalizerInput, googleKey, signal, onDelta);
  if (final.ok) {
    return {...final, provider: tier === 'ultra' ? 'wesi-maximum' : 'wesi-pro', model: 'ensemble'};
  }
  if (!final.emitted && prepared.fallback?.answer) {
    onDelta(prepared.fallback.answer);
    return {
      ok: true,
      answer: prepared.fallback.answer,
      emitted: true,
      provider: 'wesi-ensemble-fallback',
      model: 'advisor',
    };
  }
  return final;
}

'''
    stream = stream[:start] + helper + stream[end:]
    stream = stream.replace(
        "export async function streamTextRoute(route, input, googleKey, signal, onDelta) {",
        "export async function streamTextRoute(route, input, googleKey, signal, onDelta, options = {}) {",
        1,
    )
    stream = stream.replace("  const secrets = providerSecrets();", "  const secrets = options.secrets || providerSecrets();", 1)
    old = r'''  if (tier === 'pro') {
    return firstAvailableStream([
      {provider: 'groq', model: 'openai/gpt-oss-120b'},
      {provider: 'google', model: 'gemini-3.5-flash'},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets, signal, onDelta);
  }
  return callUltraStream(input, googleKey, secrets, signal, onDelta);
}'''
    new = r'''  if (tier === 'pro') return streamEnsemble('pro', input, googleKey, secrets, signal, onDelta);
  return streamEnsemble('ultra', input, googleKey, secrets, signal, onDelta);
}'''
    if old not in stream:
        raise SystemExit("stream routing tail anchor missing")
    stream = stream.replace(old, new, 1)
    write(stream_path, stream)

# 6) Regression tests: routing semantics and the two deployment bugs found in
# the live emergency activation.
ensemble_test = r'''import test from 'node:test';
import assert from 'node:assert/strict';
import {callTextRoute} from './google.mjs';

function responseJson(data, status = 200) {
  return {ok: status >= 200 && status < 300, status, async json() { return data; }};
}

function googleAnswer(text) {
  return responseJson({candidates: [{content: {parts: [{text}]}}]});
}

function openAiAnswer(text) {
  return responseJson({choices: [{message: {content: text}}]});
}

test('Fast remains latency-first and does not fan out when Gemini succeeds', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return googleAnswer('FAST_OK');
  };
  try {
    const result = await callTextRoute('wesi/fast', {system: 'persona', history: [], message: 'hi'}, 'g-key', {
      secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'},
    });
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'FAST_OK');
    assert.equal(calls.length, 1);
    assert.match(calls[0], /generativelanguage\.googleapis\.com/);
  } finally {
    globalThis.fetch = original;
  }
});

test('Pro consults independent advisors and Gemini alone produces the final answer', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    const body = JSON.parse(String(options.body || '{}'));
    calls.push({target, body});
    if (target.includes('api.groq.com')) {
      assert.match(body.messages[0].content, /WESI_AI_ADVISOR_ROLE/);
      return openAiAnswer('groq analysis');
    }
    if (target.includes('api.mistral.ai')) {
      assert.match(body.messages[0].content, /WESI_AI_ADVISOR_ROLE/);
      return openAiAnswer('mistral analysis');
    }
    if (target.includes('generativelanguage.googleapis.com')) {
      const system = body.systemInstruction.parts[0].text;
      assert.match(system, /WESI_AI_TOOL_PROTOCOL/);
      assert.match(system, /WESI_AI_ENSEMBLE_FINALIZER/);
      const finalMessage = body.contents.at(-1).parts[0].text;
      assert.match(finalMessage, /groq analysis/);
      assert.match(finalMessage, /mistral analysis/);
      return googleAnswer('PRO_FINAL');
    }
    throw new Error(`unexpected provider ${target}`);
  };
  try {
    const result = await callTextRoute('wesi/pro', {
      system: '[WESI_AI_TOOL_PROTOCOL]\nOnly finalizer may select a tool.',
      history: [],
      message: 'analyze this',
    }, 'g-key', {secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'}});
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'PRO_FINAL');
    assert.equal(result.provider, 'wesi-pro');
    assert.equal(calls.filter((c) => c.target.includes('generativelanguage')).length, 1);
    assert.equal(calls.length, 3);
  } finally {
    globalThis.fetch = original;
  }
});

test('Maximum consults all configured non-Gemini providers before Gemini synthesis', async () => {
  const original = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    const body = JSON.parse(String(options.body || '{}'));
    if (target.includes('api.groq.com')) { seen.push('groq'); return openAiAnswer('A'); }
    if (target.includes('api.mistral.ai')) { seen.push('mistral'); return openAiAnswer('B'); }
    if (target.includes('openrouter.ai')) { seen.push('openrouter'); return openAiAnswer('C'); }
    if (target.includes('generativelanguage.googleapis.com')) {
      seen.push('gemini-final');
      const finalMessage = body.contents.at(-1).parts[0].text;
      assert.match(finalMessage, /Аналитик 1/);
      assert.match(finalMessage, /Аналитик 2/);
      assert.match(finalMessage, /Аналитик 3/);
      return googleAnswer('MAX_FINAL');
    }
    throw new Error(`unexpected provider ${target}`);
  };
  try {
    const result = await callTextRoute('wesi/ultra', {system: 'persona', history: [], message: 'hard task'}, 'g-key', {
      secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'},
    });
    assert.equal(result.answer, 'MAX_FINAL');
    assert.equal(result.provider, 'wesi-maximum');
    assert.deepEqual(new Set(seen.slice(0, 3)), new Set(['groq', 'mistral', 'openrouter']));
    assert.equal(seen.at(-1), 'gemini-final');
  } finally {
    globalThis.fetch = original;
  }
});
'''
write("server/wesi-ai-relay/ensemble.test.mjs", ensemble_test)

deploy_test = r'''import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Relay installer includes every runtime module required by server imports', () => {
  const deploy = fs.readFileSync('server/wesi-ai-relay/deploy-relay.sh', 'utf8');
  assert.match(deploy, /text-stream\.mjs/);
  assert.match(deploy, /staged-upload\.mjs/);
  assert.match(deploy, /GROQ_API_KEY_B64/);
  assert.match(deploy, /MISTRAL_API_KEY_B64/);
  assert.match(deploy, /OPENROUTER_API_KEY_B64/);
});

test('Relay nginx template stays compatible with the deployed nginx generation', () => {
  const nginx = fs.readFileSync('server/wesi-ai-relay/nginx-relay.conf', 'utf8');
  assert.match(nginx, /listen 443 ssl http2;/);
  assert.doesNotMatch(nginx, /\n\s*http2 on;/);
});

test('Both production workflows seal optional advisor credentials to Relay', () => {
  for (const path of ['.github/workflows/deploy-wesi-ai.yml', '.github/workflows/deploy-wesi-ai-streaming.yml']) {
    const text = fs.readFileSync(path, 'utf8');
    for (const key of ['GROQ_API_KEY_B64', 'MISTRAL_API_KEY_B64', 'OPENROUTER_API_KEY_B64']) {
      assert.match(text, new RegExp(key), `${path} missing ${key}`);
    }
  }
});

test('Streaming Pro and Maximum route through hidden advisors then Gemini finalizer', () => {
  const text = fs.readFileSync('server/wesi-ai-relay/text-stream.mjs', 'utf8');
  assert.match(text, /streamEnsemble\('pro'/);
  assert.match(text, /streamEnsemble\('ultra'/);
  assert.match(text, /prepareWesiEnsemble/);
});
'''
write("server/wesi-ai-relay/deploy-orchestration.test.mjs", deploy_test)

# README status must match the real routing contract.
readme_path = "server/wesi-ai-relay/README.md"
readme = read(readme_path)
marker = "## Multi-AI orchestration"
if marker not in readme:
    readme += r'''

## Multi-AI orchestration

Text tiers are intentionally different:

- **Fast** is latency-first: one fast provider answers, with ordered fallback only.
- **Pro** asks two independent non-Gemini advisors in parallel. If one seat is unavailable, OpenRouter may fill it. Gemini receives the original persona/tool context plus advisor notes and is the sole finalizer.
- **Maximum** asks every configured non-Gemini advisor (Groq, Mistral, OpenRouter) in parallel, then Gemini performs the final synthesis.

Advisor outputs are never treated as verified WesiOS actions. They are hidden analytical notes. Only the Gemini finalizer can emit the final `wesiTool` envelope, and Main Server remains the only component that can verify/execute that tool through the Action Broker. If Gemini is temporarily unavailable after advisor work, chat may return one advisor answer as an availability fallback, but no advisor result is ever treated as an executed tool result.

Attachments remain Gemini-only until the non-Gemini adapters gain a verified multimodal transport; files are never silently dropped to make ensemble routing work.
'''
    write(readme_path, readme)

print("multi-provider patch applied")
