from pathlib import Path

# Fix the client override in the main patch and preserve the selected mode.
p = Path('scripts/patch_wesi_ai_dynamic_deliberation.py')
text = p.read_text(encoding='utf-8')
old = '''replace_once(\n    managed,\n    "      startDrain: false,\\n      intent: intent,\\n    );\\n",\n    "      startDrain: false,\\n      intent: intent,\\n      thinkingMode: true,\\n    );\\n",\n)'''
new = '''replace_once(\n    managed,\n    "      startDrain: false,\\n      intent: intent,\\n    );\\n",\n    "      startDrain: false,\\n      intent: intent,\\n      thinkingMode: thinkingMode,\\n    );\\n",\n)\nreplace_once(\n    managed,\n    "  @override\\n  Future<void> addUserMessage(\\n    String text, {\\n    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],\\n  }) async {\\n",\n    "  @override\\n  Future<void> addUserMessage(\\n    String text, {\\n    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],\\n    bool thinkingMode = true,\\n  }) async {\\n",\n)'''
if text.count(old) != 1:
    raise SystemExit(f'managed override patch marker count={text.count(old)}')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

# Extend the current-gateway adapter with one model-authored working-position checkpoint.
g = Path('scripts/fix_dynamic_gateway_patch.py')
gtext = g.read_text(encoding='utf-8')
old_import = "  createDeliberationState,\\n  initialDeliberationInput,\\n  parsePublicDeliberation,"
new_import = "  createDeliberationState,\\n  finalDeliberationInput,\\n  initialDeliberationInput,\\n  parsePublicDeliberation,"
if gtext.count(old_import) != 1:
    raise SystemExit(f'gateway import marker count={gtext.count(old_import)}')
gtext = gtext.replace(old_import, new_import, 1)

marker = '''replace_once(\n    gateway,\n    "        writeNdjson(res, {\\n          type: 'tool',\\n          phase: 'result','''
if marker not in gtext:
    raise SystemExit('tool patch marker not found in gateway adapter')
checkpoint = r'''replace_once(
    gateway,
    "      const toolResults = [];\n      const seenCalls = new Set();\n",
    "      if (deliberationState?.remaining > 0) {\n        try {\n          const rawPosition = await bufferedPublicModel({\n            relayUrl,\n            relaySecret,\n            prepared: leadPrepared,\n            input: finalDeliberationInput(leadPrepared, deliberationState),\n            requestId: `${prepared.requestId}_public_position`,\n            signal: abort.signal,\n            fetchImpl,\n          });\n          const parsedPosition = parsePublicDeliberation(rawPosition, {maxNotes: 1});\n          if (parsedPosition) {\n            for (const note of appendDeliberation(deliberationState, parsedPosition)) {\n              writeNdjson(res, publicNoteEvent(note));\n            }\n          }\n        } catch (positionError) {\n          if (abort.signal.aborted) throw positionError;\n        }\n      }\n\n      const toolResults = [];\n      const seenCalls = new Set();\n",
)

'''
gtext = gtext.replace(marker, checkpoint + marker, 1)
g.write_text(gtext, encoding='utf-8')
print('MANAGED_OVERRIDE_AND_CHECKPOINT_FIXED')
