import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, 'wesi_ai_stream.pb.js'), 'utf8');

test('stream prepare accepts the current smart Lobby mode sent by ordinary Zane/Nirvana chats', () => {
  assert.match(
    source,
    /lobbyMode\s*!==\s*"smart"\s*&&\s*lobbyMode\s*!==\s*"both"/,
  );
});

test('generic persona streaming stays scoped to concrete personas, not Lobby', () => {
  assert.match(source, /persona\s*!==\s*"zane"\s*&&\s*persona\s*!==\s*"nirvana"/);
});

test('stream prepare keeps active organization in runtime context', () => {
  assert.match(source, /activeOrganizationId/);
});
