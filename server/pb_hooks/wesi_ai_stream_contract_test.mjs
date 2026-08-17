import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, 'wesi_ai_stream.pb.js'), 'utf8');

test('stream prepare accepts the current smart Lobby mode sent by ordinary Zane/Nirvana chats', () => {
  assert.ok(
    source.includes('["both", "smart"].indexOf(lobbyMode) < 0'),
    'stream prepare must allow both current client lobbyMode values',
  );
});

test('generic persona streaming stays scoped to concrete personas, not Lobby', () => {
  assert.ok(
    source.includes('["zane", "nirvana"].indexOf(persona) < 0'),
    'generic stream prepare must remain scoped to concrete personas',
  );
});

test('stream prepare keeps active organization in runtime context', () => {
  assert.match(source, /activeOrganizationId/);
});

test('stream prepare bounds historical context instead of rejecting long prior replies', () => {
  assert.ok(
    source.includes('const cleanHistory = ai.sanitizeHistory(history);'),
    'stream prepare must use the shared bounded history sanitizer',
  );
  assert.ok(
    !source.includes('Слишком длинное сообщение в контексте'),
    'a long prior reply must not permanently poison a direct chat',
  );
});

test('stream prepare conversation id limit matches ordinary Main chat', () => {
  assert.ok(source.includes('conversationId.length > 180'));
});

