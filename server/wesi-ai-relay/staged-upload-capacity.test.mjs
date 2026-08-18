import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wesi-ai-stage-capacity-test-'));
process.env.WESI_RELAY_UPLOAD_DIR = root;

const staged = await import(`./staged-upload.mjs?capacity=${Date.now()}`);

function cancelAll(ids) {
  for (const id of ids) {
    staged.cancelStagedUpload({uploadId: id});
  }
}

test.after(() => {
  fs.rmSync(root, {recursive: true, force: true});
});

test('staged uploads reserve at most one GiB of declared active storage', () => {
  const ids = [];
  try {
    for (let index = 0; index < 4; index++) {
      ids.push(staged.startStagedUpload({
        name: `reserved-${index}.bin`,
        mimeType: 'application/octet-stream',
        byteSize: staged.STAGED_MAX_FILE_BYTES,
      }).id);
    }
    assert.equal(staged.STAGED_MAX_ACTIVE_BYTES, 4 * staged.STAGED_MAX_FILE_BYTES);
    assert.throws(() => staged.startStagedUpload({
      name: 'over-capacity.bin',
      mimeType: 'application/octet-stream',
      byteSize: 1,
    }), /WAI_UPLOAD_CAPACITY/);
  } finally {
    cancelAll(ids);
  }

  const recovered = staged.startStagedUpload({
    name: 'after-release.bin',
    mimeType: 'application/octet-stream',
    byteSize: 1,
  });
  staged.cancelStagedUpload({uploadId: recovered.id});
});

test('staged uploads cap the number of active sessions', () => {
  const ids = [];
  try {
    for (let index = 0; index < staged.STAGED_MAX_ACTIVE_UPLOADS; index++) {
      ids.push(staged.startStagedUpload({
        name: `session-${index}.bin`,
        mimeType: 'application/octet-stream',
        byteSize: 1,
      }).id);
    }
    assert.throws(() => staged.startStagedUpload({
      name: 'session-overflow.bin',
      mimeType: 'application/octet-stream',
      byteSize: 1,
    }), /WAI_UPLOAD_CAPACITY/);
  } finally {
    cancelAll(ids);
  }
});
