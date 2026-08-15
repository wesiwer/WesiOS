#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'lib/features/ai/ai_assistant_v2_screen.dart'
text = path.read_text(encoding='utf-8')
old = "import 'widgets/wesi_ai_message_actions.dart';\n"
new = "import 'widgets/wesi_ai_message_actions.dart';\nimport 'widgets/wesi_ai_rich_message.dart';\n"
if new not in text:
    if old not in text:
        raise SystemExit('message actions import anchor not found')
    text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')
print('contextual chat import fix applied')
