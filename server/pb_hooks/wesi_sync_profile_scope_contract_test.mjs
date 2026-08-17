import assert from "node:assert/strict";
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
