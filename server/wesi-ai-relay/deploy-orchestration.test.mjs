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
