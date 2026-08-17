from pathlib import Path

p = Path('scripts/patch_wesi_ai_dynamic_deliberation.py')
text = p.read_text(encoding='utf-8')
old = '''replace_once(\n    managed,\n    "      intent: intent,\\n    );\\n",\n    "      intent: intent,\\n      thinkingMode: thinkingMode,\\n    );\\n",\n)'''
new = '''replace_once(\n    managed,\n    "      attachments: List<WesiAiAttachment>.unmodifiable(attachments),\\n      queuedAt: queuedAt,\\n      intent: intent,\\n    );\\n",\n    "      attachments: List<WesiAiAttachment>.unmodifiable(attachments),\\n      queuedAt: queuedAt,\\n      intent: intent,\\n      thinkingMode: thinkingMode,\\n    );\\n",\n)'''
if text.count(old) != 1:
    raise SystemExit(f'ambiguous patch block match count={text.count(old)}')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
print('PATCH_AMBIGUITY_FIXED')
