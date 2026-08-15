from pathlib import Path

p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')

old = '      return result.interrupted ? null : result.value;'
new = '      return result.$1 ? null : result.$2;'
if old not in s:
    raise SystemExit('missing positional-record fix anchor')
s = s.replace(old, new, 1)

# Leaving/disposing the chat screen is not a user CONTROL command. Accepted
# lightweight work must be allowed to finish and persist after UI disposal.
old_dispose = '  void dispose() {\n    interruptActiveTurn();\n    _disposed = true;'
new_dispose = '  void dispose() {\n    _disposed = true;'
if old_dispose not in s:
    raise SystemExit('missing dispose interruption fix anchor')
s = s.replace(old_dispose, new_dispose, 1)

p.write_text(s, encoding='utf-8')
