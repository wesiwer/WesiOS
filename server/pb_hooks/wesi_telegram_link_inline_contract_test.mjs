import assert from "node:assert/strict";
import fs from "node:fs";

const source = fs.readFileSync(new URL("./wesi_telegram.pb.js", import.meta.url), "utf8");

assert.match(source, /routerAdd\("POST", "\/api\/wesi\/telegram\/link\/create"/);
assert.doesNotMatch(source, /gateway\.createLink\(e\)/);
assert.match(source, /createdAtMs:\s*nowMs/);
assert.match(source, /expiresAtMs:\s*expiresAtMs/);
assert.match(source, /runtimeVersion:\s*3/);
assert.match(source, /text\.match\(\/\^\\\/start/);
assert.match(source, /const expiresAtMs = Number\(payload\.expiresAtMs\)/);
assert.match(source, /validNumericTtl/);
assert.match(source, /record\.set\("deleted", true\)/);
assert.match(source, /store\.saveLink\(e\.app/);

console.log("TELEGRAM_LINK_INLINE_V3_OK");
