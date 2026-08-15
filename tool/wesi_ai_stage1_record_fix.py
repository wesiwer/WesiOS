from pathlib import Path

p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
old = '      return result.interrupted ? null : result.value;'
new = '      return result.$1 ? null : result.$2;'
if old not in s:
    raise SystemExit('missing positional-record fix anchor')
p.write_text(s.replace(old, new, 1), encoding='utf-8')
