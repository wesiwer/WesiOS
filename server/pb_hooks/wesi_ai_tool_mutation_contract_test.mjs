import assert from "node:assert/strict";
import fs from "node:fs";
import {test} from "node:test";

function read(path) { return fs.readFileSync(path, "utf8"); }

test("stream and Main expose authoritative capability mutation metadata", () => {
  const stream = read("server/pb_hooks/wesi_ai_stream_v2.pb.js");
  const main = read("server/pb_hooks/wesi_ai_routes.pb.js");
  for (const [name, source] of [["stream", stream], ["main", main]]) {
    assert.match(source, /capability\.risk !== registry\.RISK_READ/, name);
    assert.match(source, /mutation:/, name);
    assert.match(source, /wesi_ai_capability_registry\.js/, name);
  }
  assert.match(main, /confirmedTool/);
});

test("client refreshes sync only after verified mutations and confirmed destructive actions", () => {
  const api = read("lib/features/ai/wesi_ai_api.dart");
  const controller = read("lib/features/ai/controllers/wesi_ai_chat_controller.dart");
  const content = read("lib/features/ai/widgets/wesi_ai_message_content.dart");
  assert.match(api, /workspaceMutated/);
  assert.match(api, /item\['verified'\] != true \|\| item\['ok'\] != true/);
  assert.match(api, /capability\['mutation'\] == true/);
  assert.match(controller, /if \(reply\.workspaceMutated\)[\s\S]{0,500}SyncAuto\.now\(\)/);
  assert.match(content, /if \(result\.ok\)[\s\S]{0,500}SyncAuto\.now\(\)/);
});
