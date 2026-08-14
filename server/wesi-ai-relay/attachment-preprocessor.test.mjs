import test from 'node:test';
import assert from 'node:assert/strict';
import {sanitizeAttachments, prepareGeminiAttachments} from './attachment-preprocessor.mjs';

function item(name, mimeType, text) {
  const bytes = Buffer.from(text, 'utf8');
  return {name, mimeType, byteSize: bytes.length, dataBase64: bytes.toString('base64')};
}

test('accepts markdown and keeps content for Gemini', async () => {
  const prepared = await prepareGeminiAttachments([
    item('chat.md', 'text/markdown', '# Exported chat\nUser: hello'),
  ]);
  assert.equal(prepared.parts.length, 1);
  assert.match(prepared.parts[0].text, /Exported chat/);
});

test('rejects declared byte size mismatch', () => {
  const bad = item('a.txt', 'text/plain', 'hello');
  bad.byteSize = 999;
  assert.throws(() => sanitizeAttachments([bad]), /WAI_ATTACHMENT_SIZE_MISMATCH/);
});

test('rejects malformed base64', () => {
  assert.throws(() => sanitizeAttachments([{
    name: 'a.bin', mimeType: 'application/octet-stream', byteSize: 4, dataBase64: '***!'
  }]), /WAI_ATTACHMENT_BAD_BASE64/);
});

test('rejects more than four files', () => {
  const files = Array.from({length: 5}, (_, index) => item(`${index}.txt`, 'text/plain', 'x'));
  assert.throws(() => sanitizeAttachments(files), /WAI_ATTACHMENT_COUNT/);
});

test('image becomes native Gemini inlineData', async () => {
  const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
  const prepared = await prepareGeminiAttachments([{
    name: 'x.png', mimeType: 'image/png', byteSize: bytes.length, dataBase64: bytes.toString('base64')
  }]);
  assert.equal(prepared.parts[1].inlineData.mimeType, 'image/png');
  assert.equal(prepared.parts[1].inlineData.data, bytes.toString('base64'));
});
