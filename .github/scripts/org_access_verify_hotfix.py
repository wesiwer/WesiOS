from pathlib import Path

p = Path('lib/features/organizations/widgets/organization_access_editor.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    'MediaQuery.sizeOf(context).height.clamp(480, 720) * .72',
    'MediaQuery.sizeOf(context).height.clamp(480.0, 720.0).toDouble() * .72',
)
p.write_text(s, encoding='utf-8')
print('pre-verify hotfix applied')
