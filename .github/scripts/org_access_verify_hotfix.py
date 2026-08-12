from pathlib import Path
import re

editor = Path('lib/features/organizations/widgets/organization_access_editor.dart')
s = editor.read_text(encoding='utf-8')
s = s.replace(
    'MediaQuery.sizeOf(context).height.clamp(480, 720) * .72',
    'MediaQuery.sizeOf(context).height.clamp(480.0, 720.0).toDouble() * .72',
)
editor.write_text(s, encoding='utf-8')

contacts = Path('lib/features/team/contacts_screen.dart')
c = contacts.read_text(encoding='utf-8')
c = c.replace('  bool _canManageContext = false;\n', '')
c = c.replace(
    '        _canManageContext = selected != null && manageable.contains(selected);\n',
    '',
)
c = c.replace('        _canManageContext = false;\n', '')
c = re.sub(
    r'\n\s*_canManageContext =\s*\n?\s*organizationId != null && _manageableOrgIds\.contains\(organizationId\);',
    '',
    c,
)
contacts.write_text(c, encoding='utf-8')
print('pre-verify hotfix applied')
