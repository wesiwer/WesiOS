import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const dir = path.resolve('server/pb_hooks');
const files = fs.readdirSync(dir)
  .filter((name) => /^wesi_ai_.*\.js$/.test(name))
  .sort();

// The shared writer is the only Wesi AI module allowed to reach the sync
// atomic primitive. Individual tools must never save wesios_records directly.
test('no Wesi AI module bypasses authoritative sync writer', () => {
  const offenders = [];
  for (const name of files) {
    const source = fs.readFileSync(path.join(dir, name), 'utf8');
    if (!source.includes('wesios_records')) continue;
    if (/\be\.app\.save\s*\(/.test(source) || /\bnew\s+Record\s*\(/.test(source)) {
      offenders.push(name);
    }
  }
  assert.deepEqual(offenders, [], `direct wesios_records writers: ${offenders.join(', ')}`);
});
