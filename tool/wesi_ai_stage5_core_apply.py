from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# JSON chat path: preserve conversation id for unified audit and broker context.
replace_once(
    "server/pb_hooks/wesi_ai_routes.pb.js",
    '  const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};\n  const activeOrganizationId = String(body.activeOrganizationId || "").trim();',
    '  const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};\n  const conversationId = String(body.conversationId || "").trim();\n  const activeOrganizationId = String(body.activeOrganizationId || "").trim();',
    "direct conversation id",
)
replace_once(
    "server/pb_hooks/wesi_ai_routes.pb.js",
    '  if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");',
    '  if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100 || conversationId.length > 180) throw new BadRequestError("Слишком большой контекст Wesi AI");',
    "direct context limit",
)
replace_once(
    "server/pb_hooks/wesi_ai_routes.pb.js",
    '    const executed = tools.execute(e, ctx, toolRequest.name, toolRequest.arguments, runtimeContext.activeOrganizationId);\n    toolResults.push({tool: toolRequest.name, verified: true, ok: executed.ok === true, code: executed.code || null, message: executed.message || null, alternatives: executed.alternatives || null, result: executed.result || null});',
    '    const executed = tools.execute(e, ctx, toolRequest.name, toolRequest.arguments, runtimeContext.activeOrganizationId, {\n      persona: persona, conversationId: conversationId, requestId: requestId\n    });\n    toolResults.push({tool: toolRequest.name, verified: true, ok: executed.ok === true, code: executed.code || null, message: executed.message || null, alternatives: executed.alternatives || null, result: executed.result || null, confirmation: executed.confirmation || null});',
    "direct broker execution",
)

confirm_route = r'''

routerAdd("POST", "/api/wesi/ai/action/confirm", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  const confirmationId = String(body.confirmationId || "").trim();
  const executed = tools.confirm(e, ctx, confirmationId);
  return e.json(200, {
    ok: true,
    toolResult: {
      tool: String((executed && executed.tool) || "confirmed_action"),
      verified: true,
      ok: executed && executed.ok === true,
      code: executed && executed.code ? executed.code : null,
      message: executed && executed.message ? executed.message : null,
      alternatives: executed && executed.alternatives ? executed.alternatives : null,
      result: executed && executed.result ? executed.result : null,
    }
  });
}, $apis.requireAuth("users"));
'''
route_path = Path("server/pb_hooks/wesi_ai_routes.pb.js")
route_text = route_path.read_text(encoding="utf-8")
if '/api/wesi/ai/action/confirm' not in route_text:
    route_path.write_text(route_text.rstrip() + confirm_route + "\n", encoding="utf-8")

# Streaming path: propagate trusted request metadata to the same broker.
replace_once(
    "server/pb_hooks/wesi_ai_stream.pb.js",
    '  const activeOrganizationId = String(body.activeOrganizationId || "").trim();\n  const allowed = tools.definitions(e, ctx).some(function(item) {',
    '  const activeOrganizationId = String(body.activeOrganizationId || "").trim();\n  const requestId = String(body.requestId || "").trim().slice(0, 180);\n  const conversationId = String(body.conversationId || "").trim().slice(0, 180);\n  const persona = String(body.persona || "").trim().slice(0, 40);\n  const allowed = tools.definitions(e, ctx).some(function(item) {',
    "stream invocation metadata",
)
replace_once(
    "server/pb_hooks/wesi_ai_stream.pb.js",
    '  const executed = tools.execute(e, ctx, name, args, activeOrganizationId);\n  return e.json(200, {',
    '  const executed = tools.execute(e, ctx, name, args, activeOrganizationId, {\n    requestId: requestId, conversationId: conversationId, persona: persona\n  });\n  return e.json(200, {',
    "stream broker execution",
)
replace_once(
    "server/pb_hooks/wesi_ai_stream.pb.js",
    '      alternatives: executed.alternatives || null,\n      result: executed.result || null\n',
    '      alternatives: executed.alternatives || null,\n      result: executed.result || null,\n      confirmation: executed.confirmation || null\n',
    "stream confirmation result",
)

# Central broker owns audit. Keep old helper as no-op so legacy calls do not
# produce duplicate critical_audit rows while preserving adapter shape.
task_path = Path("server/pb_hooks/wesi_ai_task_tools.js")
task_text = task_path.read_text(encoding="utf-8")
start = task_text.find("function recordAudit(e, ctx, entry) {")
end = task_text.find("\n}\n\nfunction loadAccess", start)
if start < 0 or end < 0:
    raise SystemExit("missing anchor: task audit helper")
task_text = task_text[:start] + "function recordAudit(e, ctx, entry) { return false; }" + task_text[end + 2:]
task_path.write_text(task_text, encoding="utf-8")
