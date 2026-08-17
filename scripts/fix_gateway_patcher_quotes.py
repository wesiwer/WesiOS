from pathlib import Path

p = Path('scripts/fix_dynamic_gateway_patch.py')
text = p.read_text(encoding='utf-8')
old_start = "replacement = r'''# 7) Integrate model-generated public deliberation into the CURRENT gateway."
new_start = 'replacement = r"""# 7) Integrate model-generated public deliberation into the CURRENT gateway.'
if text.count(old_start) != 1:
    raise SystemExit(f'start marker count={text.count(old_start)}')
text = text.replace(old_start, new_start, 1)
old_end = "\n\n'''\ntext = text[:start] + replacement + text[end:]"
new_end = '\n\n"""\ntext = text[:start] + replacement + text[end:]'
if text.count(old_end) != 1:
    raise SystemExit(f'end marker count={text.count(old_end)}')
text = text.replace(old_end, new_end, 1)
p.write_text(text, encoding='utf-8')
print('GATEWAY_PATCHER_QUOTES_FIXED')
