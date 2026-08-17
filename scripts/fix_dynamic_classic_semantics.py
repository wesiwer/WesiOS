from pathlib import Path

p = Path('scripts/patch_wesi_ai_dynamic_deliberation.py')
text = p.read_text(encoding='utf-8')
marker = "# 5) API: Classic bypasses streaming entirely; Thinking marks the body explicitly.\n"
if marker not in text:
    raise SystemExit('API marker not found')
insert = '''# 4b) Classic must not create fake streaming metadata/activity locally.\nreplace_once(\n    controller,\n    "    var streamedText = '';\\n    var streamVisible = c.persona != WesiAiPersona.lobby;\\n",\n    "    var streamedText = '';\\n    var streamVisible = thinkingMode && c.persona != WesiAiPersona.lobby;\\n",\n)\n\n'''
if insert not in text:
    text = text.replace(marker, insert + marker, 1)
p.write_text(text, encoding='utf-8')
print('CLASSIC_SEMANTICS_PATCHED')
