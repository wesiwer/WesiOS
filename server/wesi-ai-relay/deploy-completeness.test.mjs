// Всё, что Relay импортирует, должно доезжать до сервера.
//
// deploy-relay.sh раньше перечислял файлы руками. Новый модуль (speakers.mjs)
// проходил тесты, копировался на хост через scp — и не устанавливался, потому
// что в списке его не было. Relay падал бы при старте на ERR_MODULE_NOT_FOUND,
// и выглядело бы это как поломка кода, а не установки.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, readdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const script = readFileSync(path.join(dir, 'deploy-relay.sh'), 'utf8');

function sources() {
  return readdirSync(dir).filter((name) => name.endsWith('.mjs') && !name.endsWith('.test.mjs'));
}

function localImports(file) {
  const text = readFileSync(path.join(dir, file), 'utf8');
  const found = new Set();
  for (const match of text.matchAll(/from\s+'(\.\/[^']+)'/g)) found.add(match[1].slice(2));
  for (const match of text.matchAll(/import\(\s*'(\.\/[^']+)'/g)) found.add(match[1].slice(2));
  return [...found];
}

test('установка не перечисляет файлы вручную', () => {
  assert.ok(
    /for path in "\$SOURCE_DIR"\/\*\.mjs/.test(script),
    'deploy-relay.sh снова ставит фиксированный список файлов — новый модуль опять потеряется',
  );
});

test('тесты на сервер не уезжают', () => {
  assert.ok(script.includes('*.test.mjs) continue ;;'));
});

test('каждый локальный импорт существует рядом', () => {
  const present = new Set(readdirSync(dir));
  const missing = [];
  for (const file of sources()) {
    for (const dep of localImports(file)) {
      if (!present.has(dep)) missing.push(`${file} -> ${dep}`);
    }
  }
  assert.deepEqual(missing, [], `импорт указывает на отсутствующий файл: ${missing.join(', ')}`);
});

test('speakers.mjs — часть Relay, а не только тестов', () => {
  const users = sources().filter((file) => localImports(file).includes('speakers.mjs'));
  assert.ok(users.length >= 2, `speakers.mjs используется только в ${users.join(', ')}`);
});
