from pathlib import Path

files = [
    Path('server/pb_hooks/wesi_sync_read.pb.js'),
    Path('server/pb_hooks/wesi_sync_write.pb.js'),
]
old = 'const privateCollections = {"profile_private": true, "vault_private": true};'
new = 'const privateCollections = {"profile": true, "profile_private": true, "vault_private": true};'
for p in files:
    text = p.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{p}: privateCollections anchor count={text.count(old)}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

t = Path('server/pb_hooks/wesi_sync_profile_scope_contract_test.mjs')
t.write_text(r'''import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

for (const file of ["wesi_sync_read.pb.js", "wesi_sync_write.pb.js"]) {
  test(`${file} keeps profile in authenticated private scope`, () => {
    const source = fs.readFileSync(new URL(`./${file}`, import.meta.url), "utf8");
    assert.match(
      source,
      /const privateCollections = \{"profile": true, "profile_private": true, "vault_private": true\};/,
    );
  });
}

test("exact extended profile route also remains private", () => {
  const source = fs.readFileSync(new URL("./wesi_sync_extra.pb.js", import.meta.url), "utf8");
  assert.match(source, /runtime\.read\(e, "profile", "private", null, false\)/);
  assert.match(source, /runtime\.write\(e, "profile", "private", null, false\)/);
});
''', encoding='utf-8')
print('SYNC_PROFILE_SCOPE_PATCH_READY')
