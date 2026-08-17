import test from 'node:test';
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

test('Production workflows keep optional advisor credentials sealed to Relay', () => {
  const classic = fs.readFileSync('.github/workflows/deploy-wesi-ai.yml', 'utf8');
  for (const key of ['GROQ_API_KEY_B64', 'MISTRAL_API_KEY_B64', 'OPENROUTER_API_KEY_B64']) {
    assert.match(classic, new RegExp(key), `.github/workflows/deploy-wesi-ai.yml missing ${key}`);
  }

  const streaming = fs.readFileSync('.github/workflows/deploy-wesi-ai-streaming.yml', 'utf8');
  for (const key of ['GROQ_KEY', 'MISTRAL_KEY', 'OPENROUTER_KEY']) {
    assert.match(streaming, new RegExp(key), `.github/workflows/deploy-wesi-ai-streaming.yml missing ${key}`);
  }
  assert.match(streaming, /build-sealed-config\.py/);

  const builder = fs.readFileSync('server/wesi-ai-stream/build-sealed-config.py', 'utf8');
  for (const key of ['GROQ_API_KEY_B64', 'MISTRAL_API_KEY_B64', 'OPENROUTER_API_KEY_B64']) {
    assert.match(builder, new RegExp(key), `stable sealed config builder missing ${key}`);
  }
});

test('Streaming deploy must restart gateway and prove live trust parity', () => {
  const workflow = fs.readFileSync('.github/workflows/deploy-wesi-ai-streaming.yml', 'utf8');
  const installer = fs.readFileSync('server/wesi-ai-stream/deploy-stream-gateway.sh', 'utf8');
  assert.match(installer, /systemctl restart wesi-ai-stream/);
  assert.match(installer, /STREAM_GATEWAY_LIVE_SECRET_OK/);
  assert.match(workflow, /Verify live gateway trust matches Main/);
  assert.match(workflow, /WESI_AI_STREAM_TRUST_PARITY_OK/);
});

test('Streaming Pro and Maximum route through hidden advisors then Gemini finalizer', () => {
  const text = fs.readFileSync('server/wesi-ai-relay/text-stream.mjs', 'utf8');
  assert.match(text, /streamEnsemble\('pro'/);
  assert.match(text, /streamEnsemble\('ultra'/);
  assert.match(text, /prepareWesiEnsemble/);
});
