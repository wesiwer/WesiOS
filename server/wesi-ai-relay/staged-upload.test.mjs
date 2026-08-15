import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wesi-ai-stage-test-'));
process.env.WESI_RELAY_UPLOAD_DIR = root;

const staged = await import(`./staged-upload.mjs?test=${Date.now()}`);
const {prepareGeminiAttachments} = await import(`./attachment-preprocessor.mjs?test=${Date.now()}`);

test.after(() => {
  fs.rmSync(root, {recursive: true, force: true});
});

test('staged upload assembles bounded chunks and resolves opaque transport ref', async () => {
  const text = '# Wesi AI\n' + 'large staged markdown line\n'.repeat(45000);
  const source = Buffer.from(text, 'utf8');
  assert.ok(source.length > staged.STAGED_CHUNK_BYTES);

  const started = staged.startStagedUpload({
    name: 'export.md',
    mimeType: 'text/markdown',
    byteSize: source.length,
  });
  assert.equal(started.chunkSize, staged.STAGED_CHUNK_BYTES);
  assert.equal(started.chunkCount, Math.ceil(source.length / staged.STAGED_CHUNK_BYTES));

  for (let index = 0; index < started.chunkCount; index++) {
    const offset = index * started.chunkSize;
    const chunk = source.subarray(offset, Math.min(source.length, offset + started.chunkSize));
    const accepted = staged.putStagedChunk({
      uploadId: started.id,
      index,
      dataBase64: chunk.toString('base64'),
    });
    assert.equal(accepted.byteSize, chunk.length);
  }

  const transport = await staged.completeStagedUpload({uploadId: started.id});
  assert.equal(transport.mimeType, staged.STAGED_UPLOAD_MIME);
  assert.ok(transport.byteSize < 512);
  assert.ok(transport.dataBase64.length < 1024);

  const prepared = await prepareGeminiAttachments([transport]);
  assert.equal(prepared.descriptors[0].name, 'export.md');
  assert.equal(prepared.descriptors[0].byteSize, source.length);
  assert.match(prepared.parts[0].text, /WESI_AI_ATTACHMENT_TEXT export\.md/);
  assert.match(prepared.parts[0].text, /# Wesi AI/);
});

test('staged upload rejects a chunk with wrong length', () => {
  const started = staged.startStagedUpload({
    name: 'broken.bin',
    mimeType: 'application/octet-stream',
    byteSize: staged.STAGED_CHUNK_BYTES + 8,
  });
  assert.throws(() => staged.putStagedChunk({
    uploadId: started.id,
    index: 0,
    dataBase64: Buffer.from('too short').toString('base64'),
  }), /WAI_UPLOAD_CHUNK_MISMATCH/);
  staged.cancelStagedUpload({uploadId: started.id});
});

test('transport reference requires the random capability token', async () => {
  const source = Buffer.from('secret project context');
  const started = staged.startStagedUpload({
    name: 'context.txt',
    mimeType: 'text/plain',
    byteSize: source.length,
  });
  staged.putStagedChunk({
    uploadId: started.id,
    index: 0,
    dataBase64: source.toString('base64'),
  });
  const transport = await staged.completeStagedUpload({uploadId: started.id});
  const ref = JSON.parse(Buffer.from(transport.dataBase64, 'base64').toString('utf8'));
  ref.cap = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const forged = {
    ...transport,
    dataBase64: Buffer.from(JSON.stringify(ref)).toString('base64'),
  };
  assert.throws(() => staged.resolveStagedAttachment({
    name: forged.name,
    mimeType: forged.mimeType,
    byteSize: Buffer.from(forged.dataBase64, 'base64').length,
    bytes: Buffer.from(forged.dataBase64, 'base64'),
  }), /WAI_UPLOAD_REF_INVALID/);
});
