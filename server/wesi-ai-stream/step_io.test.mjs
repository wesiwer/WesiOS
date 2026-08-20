import assert from 'node:assert/strict';
import test from 'node:test';
import {MAX_STEP_IO_CHARS, stepIo} from './step_io.mjs';

test('tool step details preserve code beyond the old 4K limit', () => {
  const code = 'const value = 1;\n'.repeat(900);
  const io = stepIo(
    {arguments: {language: 'javascript', code}},
    {ok: true, result: {summary: 'Код выполнен', code}},
  );

  assert.ok(io.input.length > 4000);
  assert.ok(io.output.length > 4000);
  assert.ok(io.input.length <= MAX_STEP_IO_CHARS);
  assert.ok(io.output.length <= MAX_STEP_IO_CHARS);
  assert.match(io.input, /const value = 1/);
  assert.match(io.output, /Код выполнен/);
});

test('tool step details still enforce the protective event cap', () => {
  const huge = 'x'.repeat(MAX_STEP_IO_CHARS * 2);
  const io = stepIo({arguments: {code: huge}}, {result: {output: huge}});
  assert.equal(io.input.length, MAX_STEP_IO_CHARS);
  assert.equal(io.output.length, MAX_STEP_IO_CHARS);
});
