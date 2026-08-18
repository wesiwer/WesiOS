from pathlib import Path
import re

ROOT = Path('.')

# 1) Streaming tool-v2: attach capability metadata from the authoritative registry.
path = ROOT / 'server/pb_hooks/wesi_ai_stream_v2.pb.js'
text = path.read_text(encoding='utf-8')
old = '''  const executed = tools.execute(e, ctx, name, args, activeOrganizationId, {
    requestId: requestId,
    conversationId: conversationId,
    persona: persona,
    actorRole: actorRole,
    leadPersona: leadPersona,
    handoffId: handoffId
  });
  return e.json(200, {
    ok: true,
    toolResult: {
      tool: name,
      verified: true,
      ok: executed.ok === true,
      code: executed.code || null,
      message: executed.message || null,
      alternatives: executed.alternatives || null,
      result: executed.result || null,
      confirmation: executed.confirmation || null
    }
  });'''
new = '''  const executed = tools.execute(e, ctx, name, args, activeOrganizationId, {
    requestId: requestId,
    conversationId: conversationId,
    persona: persona,
    actorRole: actorRole,
    leadPersona: leadPersona,
    handoffId: handoffId
  });
  const capability = registry.get(name);
  return e.json(200, {
    ok: true,
    toolResult: {
      tool: name,
      verified: true,
      ok: executed.ok === true,
      code: executed.code || null,
      message: executed.message || null,
      alternatives: executed.alternatives || null,
      result: executed.result || null,
      confirmation: executed.confirmation || null,
      capability: capability ? {
        module: capability.module,
        action: capability.action,
        risk: capability.risk,
        mutation: capability.risk !== registry.RISK_READ
      } : null
    }
  });'''
if old not in text:
    raise SystemExit('stream-v2 tool result anchor not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')

# 2) Main/Lobby route: add registry in chat route and decorate every executed result.
path = ROOT / 'server/pb_hooks/wesi_ai_routes.pb.js'
text = path.read_text(encoding='utf-8')
chat_anchor = '''  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);'''
chat_repl = '''  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const registry = require(`${__hooks}/wesi_ai_capability_registry.js`);
  const ctx = ai.resolveIdentity(e);'''
if chat_anchor not in text:
    raise SystemExit('main chat registry anchor not found')
text = text.replace(chat_anchor, chat_repl, 1)

old_push = '''    toolResults.push({tool: toolRequest.name, verified: true, ok: executed.ok === true, code: executed.code || null, message: executed.message || null, alternatives: executed.alternatives || null, result: executed.result || null, confirmation: executed.confirmation || null, diagnostic: executed.ok === true ? null : diagnostic("TOOL", toolRequest.name, "tool.execute", executed.code || "WAI_TOOL_FAILED", 500, "TOOL_DISPATCH", executed.message || "")});'''
new_push = '''    const capability = registry.get(toolRequest.name);
    toolResults.push({tool: toolRequest.name, verified: true, ok: executed.ok === true, code: executed.code || null, message: executed.message || null, alternatives: executed.alternatives || null, result: executed.result || null, confirmation: executed.confirmation || null, capability: capability ? {module: capability.module, action: capability.action, risk: capability.risk, mutation: capability.risk !== registry.RISK_READ} : null, diagnostic: executed.ok === true ? null : diagnostic("TOOL", toolRequest.name, "tool.execute", executed.code || "WAI_TOOL_FAILED", 500, "TOOL_DISPATCH", executed.message || "")});'''
if old_push not in text:
    raise SystemExit('main tool result push anchor not found')
text = text.replace(old_push, new_push, 1)

# 3) Confirm route: return capability metadata after destructive execution.
confirm_anchor = '''  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);'''
# This exact pair appears in confirm route after the chat route was already modified.
pos = text.find('routerAdd("POST", "/api/wesi/ai/action/confirm"')
if pos < 0:
    raise SystemExit('confirm route not found')
tail = text[pos:]
if confirm_anchor not in tail:
    raise SystemExit('confirm registry anchor not found')
tail = tail.replace(confirm_anchor, '''  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const registry = require(`${__hooks}/wesi_ai_capability_registry.js`);
  const ctx = ai.resolveIdentity(e);''', 1)
text = text[:pos] + tail

confirm_exec_anchor = '''  const confirmationId = String(body.confirmationId || "").trim();
  const executed = tools.confirm(e, ctx, confirmationId);
  return e.json(200, {'''
confirm_exec_repl = '''  const confirmationId = String(body.confirmationId || "").trim();
  const executed = tools.confirm(e, ctx, confirmationId);
  const confirmedTool = String((executed && executed.tool) || "confirmed_action");
  const capability = registry.get(confirmedTool);
  return e.json(200, {'''
if confirm_exec_anchor not in text:
    raise SystemExit('confirm execution anchor not found')
text = text.replace(confirm_exec_anchor, confirm_exec_repl, 1)
text = text.replace('''      tool: String((executed && executed.tool) || "confirmed_action"),''', '''      tool: confirmedTool,''', 1)
confirm_result_anchor = '''      alternatives: executed && executed.alternatives ? executed.alternatives : null,
      result: executed && executed.result ? executed.result : null'''
confirm_result_repl = '''      alternatives: executed && executed.alternatives ? executed.alternatives : null,
      result: executed && executed.result ? executed.result : null,
      capability: capability ? {
        module: capability.module,
        action: capability.action,
        risk: capability.risk,
        mutation: capability.risk !== registry.RISK_READ
      } : null'''
if confirm_result_anchor not in text:
    raise SystemExit('confirm result anchor not found')
text = text.replace(confirm_result_anchor, confirm_result_repl, 1)
path.write_text(text, encoding='utf-8')

# 4) Client reply: preserve whether verified server tools mutated workspace.
path = ROOT / 'lib/features/ai/wesi_ai_api.dart'
text = path.read_text(encoding='utf-8')
reply_anchor = '''  final List<WesiAiContentBlock> blocks;
  final List<Map<String, dynamic>> activity;

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
    this.activity = const <Map<String, dynamic>>[],
  });'''
reply_repl = '''  final List<WesiAiContentBlock> blocks;
  final List<Map<String, dynamic>> activity;
  final bool workspaceMutated;

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
    this.activity = const <Map<String, dynamic>>[],
    this.workspaceMutated = false,
  });'''
if reply_anchor not in text:
    raise SystemExit('WesiAiReply anchor not found')
text = text.replace(reply_anchor, reply_repl, 1)

return_anchor = '''      activity: _activityFromToolResults(json['toolResults']),
    );
  }

  static List<Map<String, dynamic>> _activityFromToolResults(dynamic raw) {'''
return_repl = '''      activity: _activityFromToolResults(json['toolResults']),
      workspaceMutated: _workspaceMutatedFromToolResults(json['toolResults']),
    );
  }

  static bool _workspaceMutatedFromToolResults(dynamic raw) {
    if (raw is! List) return false;
    for (final item in raw) {
      if (item is! Map || item['verified'] != true || item['ok'] != true) continue;
      final capabilityRaw = item['capability'];
      if (capabilityRaw is! Map) continue;
      final capability = Map<String, dynamic>.from(capabilityRaw);
      if (capability['mutation'] == true) return true;
    }
    return false;
  }

  static List<Map<String, dynamic>> _activityFromToolResults(dynamic raw) {'''
if return_anchor not in text:
    raise SystemExit('reply return anchor not found')
text = text.replace(return_anchor, return_repl, 1)
path.write_text(text, encoding='utf-8')

# 5) Controller: after verified mutation, stabilize cross-device state before saving assistant reply.
path = ROOT / 'lib/features/ai/controllers/wesi_ai_chat_controller.dart'
text = path.read_text(encoding='utf-8')
import_anchor = "import 'package:flutter/foundation.dart';\n\n"
if import_anchor not in text:
    raise SystemExit('controller import anchor not found')
text = text.replace(import_anchor, "import 'package:flutter/foundation.dart';\n\nimport '../../../core/sync/sync_auto.dart';\n\n", 1)
final_anchor = '''      final at = DateTime.now();
      final assistant = WesiAiMessage('''
final_repl = '''      if (reply.workspaceMutated) {
        final syncReport = await SyncAuto.now();
        final failure = syncReport.firstFailure;
        activity.add(activityEntry(
          kind: 'status',
          label: syncReport.ok
              ? 'Изменения WesiOS синхронизированы'
              : 'Изменение выполнено, Sync не завершён',
          detail: syncReport.ok
              ? 'Серверное изменение применено и локальное состояние стабилизировано.'
              : 'Код Sync: ${failure?.code ?? 'UNKNOWN'} · ${failure?.message ?? 'Не удалось стабилизировать локальные данные'}',
          status: syncReport.ok ? 'done' : 'error',
        ));
      }
      final at = DateTime.now();
      final assistant = WesiAiMessage('''
if final_anchor not in text:
    raise SystemExit('controller final assistant anchor not found')
text = text.replace(final_anchor, final_repl, 1)
path.write_text(text, encoding='utf-8')

# 6) Confirmation card: destructive confirmation also stabilizes Sync after successful server execution.
path = ROOT / 'lib/features/ai/widgets/wesi_ai_message_content.dart'
text = path.read_text(encoding='utf-8')
widget_import_anchor = "import 'package:video_player/video_player.dart';\n\n"
if widget_import_anchor not in text:
    raise SystemExit('message content import anchor not found')
text = text.replace(widget_import_anchor, "import 'package:video_player/video_player.dart';\n\nimport '../../../core/sync/sync_auto.dart';\n\n", 1)
confirm_anchor = '''    setState(() => _running = true);
    final result = await const WesiAiActionApi().confirm(id);
    if (!mounted) return;
    setState(() {
      _running = false;
      _success = result.ok;
      _message = result.ok
          ? 'Действие выполнено.'
          : (result.message ?? 'Не удалось выполнить действие.');
      _terminal =
          result.ok ||
          (result.code != null &&
              result.code != 'NETWORK' &&
              result.code != 'WAI_CONFIRMATION_BAD_RESPONSE');
    });'''
confirm_repl = '''    setState(() => _running = true);
    final result = await const WesiAiActionApi().confirm(id);
    String? syncFailure;
    if (result.ok) {
      final syncReport = await SyncAuto.now();
      if (!syncReport.ok) {
        final failure = syncReport.firstFailure;
        syncFailure = 'Действие выполнено на сервере, но Sync не завершён: ${failure?.code ?? 'UNKNOWN'} · ${failure?.message ?? 'ошибка синхронизации'}';
      }
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _success = result.ok;
      _message = result.ok
          ? (syncFailure ?? 'Действие выполнено, данные синхронизированы.')
          : (result.message ?? 'Не удалось выполнить действие.');
      _terminal =
          result.ok ||
          (result.code != null &&
              result.code != 'NETWORK' &&
              result.code != 'WAI_CONFIRMATION_BAD_RESPONSE');
    });'''
if confirm_anchor not in text:
    raise SystemExit('confirmation sync anchor not found')
text = text.replace(confirm_anchor, confirm_repl, 1)
path.write_text(text, encoding='utf-8')

# 7) Contract tests (source + functional mutation parser test through public reply parse behavior is covered statically here).
test_path = ROOT / 'server/pb_hooks/wesi_ai_tool_mutation_contract_test.mjs'
test_path.write_text('''import assert from "node:assert/strict";\nimport fs from "node:fs";\nimport {test} from "node:test";\n\nfunction read(path) { return fs.readFileSync(path, "utf8"); }\n\ntest("stream and Main expose authoritative capability mutation metadata", () => {\n  const stream = read("server/pb_hooks/wesi_ai_stream_v2.pb.js");\n  const main = read("server/pb_hooks/wesi_ai_routes.pb.js");\n  for (const [name, source] of [["stream", stream], ["main", main]]) {\n    assert.match(source, /capability\.risk !== registry\.RISK_READ/, name);\n    assert.match(source, /mutation:/, name);\n    assert.match(source, /wesi_ai_capability_registry\.js/, name);\n  }\n  assert.match(main, /confirmedTool/);\n});\n\ntest("client refreshes sync only after verified mutations and confirmed destructive actions", () => {\n  const api = read("lib/features/ai/wesi_ai_api.dart");\n  const controller = read("lib/features/ai/controllers/wesi_ai_chat_controller.dart");\n  const content = read("lib/features/ai/widgets/wesi_ai_message_content.dart");\n  assert.match(api, /workspaceMutated/);\n  assert.match(api, /item\['verified'\] != true \|\| item\['ok'\] != true/);\n  assert.match(api, /capability\['mutation'\] == true/);\n  assert.match(controller, /if \(reply\.workspaceMutated\)[\s\S]{0,500}SyncAuto\.now\(\)/);\n  assert.match(content, /if \(result\.ok\)[\s\S]{0,500}SyncAuto\.now\(\)/);\n});\n''', encoding='utf-8')

# Strip trailing whitespace in touched files.
for rel in [
    'server/pb_hooks/wesi_ai_stream_v2.pb.js',
    'server/pb_hooks/wesi_ai_routes.pb.js',
    'lib/features/ai/wesi_ai_api.dart',
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    'lib/features/ai/widgets/wesi_ai_message_content.dart',
    'server/pb_hooks/wesi_ai_tool_mutation_contract_test.mjs',
]:
    p = ROOT / rel
    lines = p.read_text(encoding='utf-8').splitlines()
    p.write_text('\n'.join(line.rstrip() for line in lines) + '\n', encoding='utf-8')

print('AI_TOOL_MUTATION_SYNC_PATCH_READY')
