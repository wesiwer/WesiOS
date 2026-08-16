import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const media = require('./wesi_ai_media_contract.js');
const tools = require('./wesi_ai_media_tools.js');
const registry = require('./wesi_ai_capability_registry.js');

const expectedTools = [
  'generate_image',
  'edit_image',
  'reference_image',
  'generate_music',
  'separate_music_stems',
  'generate_video',
  'compose_video',
  'add_video_voice',
  'add_video_sfx',
  'add_video_subtitles',
];

test('generation workflows are explicit and input-free', () => {
  for (const [workflow, expectedType] of [
    ['imageGenerate', 'image'],
    ['musicGenerate', 'music'],
    ['videoGenerate', 'video'],
  ]) {
    const result = media.normalize(workflow, {prompt: 'generate test'});
    assert.equal(result.ok, true);
    assert.equal(result.request.mediaType, expectedType);
    assert.equal(result.request.workflow, workflow);
    assert.equal(result.request.options.workflow, workflow);
    assert.deepEqual(result.request.attachmentIndexes, []);
  }
});

test('input workflow accepts only current-turn attachment indexes', () => {
  const result = media.normalize('imageEdit', {
    prompt: 'remove background',
    attachmentIndex: 1,
    inputPath: '/etc/passwd',
    inputPaths: ['/tmp/model-controlled'],
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.request.attachmentIndexes, [1]);
  assert.equal('inputPath' in result.request, false);
  assert.equal('inputPaths' in result.request, false);
  assert.equal('inputs' in result.request.options, false);
});

test('input workflow rejects missing, duplicate, and out-of-range indexes', () => {
  assert.equal(media.normalize('musicStems', {}).code, 'WAI_MEDIA_INPUT_REQUIRED');
  assert.equal(media.normalize('videoCompose', {prompt: 'compose', attachmentIndexes: [0, 0]}).code, 'WAI_MEDIA_INPUT_REQUIRED');
  assert.equal(media.normalize('videoCompose', {prompt: 'compose', attachmentIndexes: [4]}).code, 'WAI_MEDIA_INPUT_REQUIRED');
});

test('voice workflow requires exactly video and voice attachment indexes', () => {
  const ok = media.normalize('videoVoice', {
    videoAttachmentIndex: 0,
    voiceAttachmentIndex: 2,
  });
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.request.attachmentIndexes, [0, 2]);
  assert.equal(ok.request.prompt.length > 0, true);

  const missing = media.normalize('videoVoice', {videoAttachmentIndex: 0});
  assert.equal(missing.ok, false);
  assert.equal(missing.code, 'WAI_MEDIA_INPUT_REQUIRED');
});

test('all Stage14 media tools are exposed and registered as media WRITE', () => {
  const definitions = tools.definitions();
  const names = definitions.map((item) => item.name);
  for (const name of expectedTools) {
    assert.equal(names.includes(name), true, `${name} definition missing`);
    const meta = registry.get(name);
    assert.ok(meta, `${name} capability missing`);
    assert.equal(meta.module, 'media');
    assert.equal(meta.action, 'generate');
    assert.equal(meta.risk, 'WRITE');
    assert.equal(meta.confirmationRequired, false);
  }
});

test('input tools emit only normalized workflow and attachment indexes', () => {
  const edit = tools.execute(null, {}, 'edit_image', {
    prompt: 'remove background',
    attachmentIndex: 0,
    inputPath: '/etc/passwd',
  });
  assert.equal(edit.ok, true);
  assert.equal(edit.result.localMediaRequest.workflow, 'imageEdit');
  assert.deepEqual(edit.result.localMediaRequest.attachmentIndexes, [0]);
  assert.equal('inputPath' in edit.result.localMediaRequest, false);

  const voice = tools.execute(null, {}, 'add_video_voice', {
    videoAttachmentIndex: 0,
    voiceAttachmentIndex: 1,
  });
  assert.equal(voice.ok, true);
  assert.equal(voice.result.localMediaRequest.workflow, 'videoVoice');
  assert.deepEqual(voice.result.localMediaRequest.attachmentIndexes, [0, 1]);
});

test('unknown workflows fail closed', () => {
  const result = media.normalize('shellExec', {prompt: 'x'});
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_MEDIA_WORKFLOW_FORBIDDEN');
});
