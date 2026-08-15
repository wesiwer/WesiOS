from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    return text.replace(old, new, 1)


# Relay: add real NDJSON endpoint backed by provider SSE.
p = Path('server/wesi-ai-relay/server.mjs')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import {callTextRoute} from './google.mjs';\n",
    "import {callTextRoute} from './google.mjs';\nimport {streamTextRoute} from './text-stream.mjs';\n",
    'relay stream import',
)
s = replace_once(
    s,
    "      routing: ['fast', 'pro', 'ultra'],\n",
    "      routing: ['fast', 'pro', 'ultra'],\n      streaming: true,\n",
    'relay health streaming',
)
s = replace_once(
    s,
    "  const isMain = req.method === 'POST' && req.url === '/v1/wesi-ai';\n  const isArtifact = req.method === 'POST' && req.url === '/v1/wesi-ai-artifact';\n  if (!isMain && !isArtifact) return send(res, 404, {ok: false, code: 'NOT_FOUND'});",
    "  const isMain = req.method === 'POST' && req.url === '/v1/wesi-ai';\n  const isStream = req.method === 'POST' && req.url === '/v1/wesi-ai-stream';\n  const isArtifact = req.method === 'POST' && req.url === '/v1/wesi-ai-artifact';\n  if (!isMain && !isStream && !isArtifact) return send(res, 404, {ok: false, code: 'NOT_FOUND'});",
    'relay stream route detection',
)
anchor = "  if (isArtifact) {\n    const artifactId = String(request.artifactId || '');\n    const item = takeMedia(artifactId);\n    if (!item) return send(res, 404, {ok: false, code: 'WAI_RELAY_ARTIFACT_NOT_FOUND'});\n    return sendArtifact(res, item);\n  }\n\n"
stream_block = anchor + """  if (isStream) {
    if (String(request.operation || '') !== 'chat.stream') {
      return send(res, 400, {ok: false, code: 'WAI_OPERATION_UNAVAILABLE'});
    }
    res.writeHead(200, {
      'content-type': 'application/x-ndjson; charset=utf-8',
      'cache-control': 'no-store, no-transform',
      'x-content-type-options': 'nosniff',
      'x-accel-buffering': 'no',
    });
    const abort = new AbortController();
    res.on('close', () => {
      if (!res.writableEnded) abort.abort();
    });
    const writeEvent = (event) => {
      if (!res.destroyed && !res.writableEnded) res.write(`${JSON.stringify(event)}\\n`);
    };
    try {
      const result = await streamTextRoute(
        request.route,
        request.input || {},
        googleKey,
        abort.signal,
        (text) => writeEvent({type: 'delta', text}),
      );
      if (!result?.ok) {
        writeEvent({
          type: 'error',
          status: result?.status || 502,
          code: result?.code || 'WAI_PROVIDER_UNAVAILABLE',
        });
      } else {
        writeEvent({type: 'done', answer: result.answer});
      }
      res.end();
    } catch (error) {
      if (abort.signal.aborted || res.destroyed) return;
      const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
      writeEvent({type: 'error', code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'});
      res.end();
    }
    return;
  }

"""
s = replace_once(s, anchor, stream_block, 'relay stream handler')
p.write_text(s, encoding='utf-8')

# Main config knows an independent localhost gateway secret.
p = Path('server/pb_hooks/wesi_ai_lib.js')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "      const routes = cfg.routes && typeof cfg.routes === \"object\" ? cfg.routes : {};\n      return {",
    "      const routes = cfg.routes && typeof cfg.routes === \"object\" ? cfg.routes : {};\n      const streamSecret = String(cfg.streamSecret || \"\").trim();\n      return {",
    'stream secret parse',
)
s = replace_once(
    s,
    "        sharedSecret: sharedSecret,\n        routes: {",
    "        sharedSecret: sharedSecret,\n        streamSecret: streamSecret,\n        routes: {",
    'stream secret return',
)
s = replace_once(
    s,
    '      return {ready: false, url: "", sharedSecret: "", routes: {fast: "", pro: "", maximum: ""}};',
    '      return {ready: false, url: "", sharedSecret: "", streamSecret: "", routes: {fast: "", pro: "", maximum: ""}};',
    'stream secret fallback',
)
p.write_text(s, encoding='utf-8')

# Capabilities only advertise transport streaming when the Main gateway secret exists.
p = Path('server/pb_hooks/wesi_ai_routes.pb.js')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '      streaming: false,',
    '      streaming: cfg.ready && String(cfg.streamSecret || "").length >= 32,',
    'capabilities streaming',
)
p.write_text(s, encoding='utf-8')

# Main gateway supports Node 18+ (fetch is available and keeps the small VPS footprint low).
p = Path('server/wesi-ai-stream/package.json')
s = p.read_text(encoding='utf-8').replace('"node": ">=20"', '"node": ">=18"')
p.write_text(s, encoding='utf-8')

# Fix deterministic HMAC expectation in the unit test.
p = Path('server/wesi-ai-stream/gateway.test.mjs')
s = p.read_text(encoding='utf-8')
s = s.replace(
    "b121f5cc67b389a6680e5c92fdcfb6721b12def7662db71d46f90c0c62ee9450",
    "00869641839c4678dd4316b6a4d07ced9cdd8b44751bb15286e4665e39093a78",
)
p.write_text(s, encoding='utf-8')

# PR gate validates both Relay and the Main stream gateway.
p = Path('.github/workflows/pr-check.yml')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '          for file in server/pb_hooks/*.js server/employee-portal/*.js server/wesi-ai-relay/*.mjs; do',
    '          for file in server/pb_hooks/*.js server/employee-portal/*.js server/wesi-ai-relay/*.mjs server/wesi-ai-stream/*.mjs; do',
    'pr js validation',
)
s = replace_once(
    s,
    '          for file in server/wesi-ai-relay/*.sh; do',
    '          for file in server/wesi-ai-relay/*.sh server/wesi-ai-stream/*.sh; do',
    'pr shell validation',
)
s = replace_once(
    s,
    '      - name: Test Wesi AI Relay\n        run: node --test server/wesi-ai-relay/*.test.mjs\n',
    '      - name: Test Wesi AI Relay\n        run: node --test server/wesi-ai-relay/*.test.mjs\n      - name: Test Wesi AI Main streaming gateway\n        run: node --test server/wesi-ai-stream/*.test.mjs\n',
    'pr stream tests',
)
p.write_text(s, encoding='utf-8')

# Production workflow: generate an independent stream secret and deploy gateway + nginx.
p = Path('.github/workflows/deploy-wesi-ai.yml')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '          echo "::add-mask::$SHARED"\n          echo "WESI_SHARED_SECRET=$SHARED" >> "$GITHUB_ENV"',
    '          echo "::add-mask::$SHARED"\n          echo "WESI_SHARED_SECRET=$SHARED" >> "$GITHUB_ENV"\n          STREAM_SECRET="$(openssl rand -hex 32)"\n          echo "::add-mask::$STREAM_SECRET"\n          echo "WESI_STREAM_SECRET=$STREAM_SECRET" >> "$GITHUB_ENV"',
    'deploy stream secret',
)
s = replace_once(
    s,
    '          for file in server/wesi-ai-relay/*.mjs; do node --check "$file"; done\n          node --test server/wesi-ai-relay/*.test.mjs\n          bash -n server/wesi-ai-relay/deploy-relay.sh',
    '          for file in server/wesi-ai-relay/*.mjs server/wesi-ai-stream/*.mjs; do node --check "$file"; done\n          node --test server/wesi-ai-relay/*.test.mjs\n          node --test server/wesi-ai-stream/*.test.mjs\n          bash -n server/wesi-ai-relay/deploy-relay.sh\n          bash -n server/wesi-ai-stream/deploy-stream-gateway.sh\n          bash -n server/wesi-ai-stream/configure-main-nginx.sh',
    'deploy source validation',
)
s = replace_once(
    s,
    "          config={'url':'https://'+os.environ['PUBLIC_HOST'],'sharedSecret':os.environ['WESI_SHARED_SECRET'],'routes':{'fast':'wesi/fast','pro':'wesi/pro','maximum':'wesi/ultra'}}",
    "          config={'url':'https://'+os.environ['PUBLIC_HOST'],'sharedSecret':os.environ['WESI_SHARED_SECRET'],'streamSecret':os.environ['WESI_STREAM_SECRET'],'routes':{'fast':'wesi/fast','pro':'wesi/pro','maximum':'wesi/ultra'}}",
    'main relay config stream secret',
)
old = '''          python3 - <<'PY'
          import json, os
          config={'url':'https://'+os.environ['PUBLIC_HOST'],'sharedSecret':os.environ['WESI_SHARED_SECRET'],'streamSecret':os.environ['WESI_STREAM_SECRET'],'routes':{'fast':'wesi/fast','pro':'wesi/pro','maximum':'wesi/ultra'}}
          with open('wesi-ai-relay.json','w',encoding='utf-8') as f: json.dump(config,f,ensure_ascii=False)
          PY
          chmod 600 wesi-ai-relay.json
'''
new = old + '''          python3 - <<'PY'
          import base64, os
          values={
            'WESI_STREAM_SECRET_B64': os.environ['WESI_STREAM_SECRET'],
            'WESI_MAIN_SHARED_SECRET_B64': os.environ['WESI_SHARED_SECRET'],
            'WESI_RELAY_URL_B64': 'https://'+os.environ['PUBLIC_HOST'],
            'WESI_POCKETBASE_URL_B64': 'http://127.0.0.1:8090',
          }
          with open('stream-secrets.b64','w',encoding='ascii') as f:
            for key,value in values.items(): f.write(key+'='+base64.b64encode(value.encode()).decode()+'\\n')
          PY
          chmod 600 stream-secrets.b64
'''
s = replace_once(s, old, new, 'build stream env')
s = replace_once(
    s,
    '          scp "${SSH[@]}" server/pb_hooks/wesi_ai_*.js server/pb_hooks/wesi_ai_*.pb.js server/pb_hooks/.wesi-ai-personas.json wesi-ai-relay.json "$MAIN_USER@$MAIN_HOST:$MAIN_REMOTE/"',
    '          scp "${SSH[@]}" server/pb_hooks/wesi_ai_*.js server/pb_hooks/wesi_ai_*.pb.js server/pb_hooks/.wesi-ai-personas.json wesi-ai-relay.json stream-secrets.b64 "$MAIN_USER@$MAIN_HOST:$MAIN_REMOTE/"\n          scp "${SSH[@]}" -r server/wesi-ai-stream "$MAIN_USER@$MAIN_HOST:$MAIN_REMOTE/"',
    'upload main stream bundle',
)
s = replace_once(
    s,
    '          "${SUDO[@]}" systemctl restart pocketbase\n          for _ in $(seq 1 30); do systemctl is-active --quiet pocketbase && exit 0; sleep 1; done\n          systemctl is-active --quiet pocketbase',
    '          "${SUDO[@]}" systemctl restart pocketbase\n          for _ in $(seq 1 30); do systemctl is-active --quiet pocketbase && break; sleep 1; done\n          systemctl is-active --quiet pocketbase\n          bash "$REMOTE/wesi-ai-stream/deploy-stream-gateway.sh" "$REMOTE/wesi-ai-stream" "$REMOTE/stream-secrets.b64"\n          bash "$REMOTE/wesi-ai-stream/configure-main-nginx.sh"',
    'install main stream gateway',
)
s = replace_once(
    s,
    '          rm -f wesi-ai-relay.json\n',
    '          rm -f wesi-ai-relay.json stream-secrets.b64\n',
    'cleanup stream env',
)
s = replace_once(
    s,
    '          check_route GET /api/wesi/ai/capabilities\n',
    '          check_route GET /api/wesi/ai/capabilities\n          check_route POST /api/wesi/ai/chat/stream\n',
    'verify stream protection',
)
s = s.replace(
    "echo 'Wesi AI production deployment complete: Fast / Pro / Ultra + TTS + Main hooks.'",
    "echo 'Wesi AI production deployment complete: Fast / Pro / Ultra + true streaming + TTS + Main hooks.'",
)
p.write_text(s, encoding='utf-8')
