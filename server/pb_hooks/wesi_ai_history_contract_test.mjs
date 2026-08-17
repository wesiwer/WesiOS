import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const read = (name) => readFileSync(join(here, name), 'utf8');

test('Main chat, direct stream and Lobby share one bounded history sanitizer', () => {
  for (const name of ['wesi_ai_routes.pb.js', 'wesi_ai_stream.pb.js', 'wesi_ai_lobby_core.js']) {
    const source = read(name);
    assert.match(source, /ai\.sanitizeHistory\(/, `${name} must use the shared history sanitizer`);
    assert.doesNotMatch(source, /Слишком длинное сообщение в контексте/, `${name} must not poison a chat because of one old long message`);
  }
});

test('stream and ordinary Main chat use the same conversation id limit', () => {
  assert.match(read('wesi_ai_stream.pb.js'), /conversationId\.length > 180/);
  assert.match(read('wesi_ai_routes.pb.js'), /conversationId\.length > 180/);
});
