from pathlib import Path

p = Path('tools/finalize_org_remediation.py')
text = p.read_text(encoding='utf-8')
old = """orgs = 'lib/features/organizations/organizations_screen.dart'
file_replace(
    orgs,
    '  String? _error;\\n',
    '  String? _error;\\n  int _loadEpoch = 0;\\n',
    'Organizations epoch field',
)
file_replace(
    orgs,
    '  Future<void> _load() async {\\n    try {\\n',
    '  Future<void> _load() async {\\n    final epoch = ++_loadEpoch;\\n    try {\\n',
    'Organizations epoch start',
)
file_replace(
    orgs,
    '      if (!mounted) return;\\n      setState(() {\\n',
    '      if (!mounted || epoch != _loadEpoch) return;\\n      setState(() {\\n',
    'Organizations stale success',
)
file_replace(
    orgs,
    '    } catch (e) {\\n      if (mounted) {\\n',
    '    } catch (e) {\\n      if (mounted && epoch == _loadEpoch) {\\n',
    'Organizations stale error',
)
"""
new = """orgs = 'lib/features/organizations/organizations_screen.dart'
p_orgs = Path(orgs)
org_text = p_orgs.read_text(encoding='utf-8')
if 'class _OrganizationsScreenState' in org_text:
    org_start = org_text.index('class _OrganizationsScreenState')
    org_end = org_text.index('\\nclass ', org_start + 1)
    org_block = org_text[org_start:org_end]
    if 'int _loadEpoch = 0;' not in org_block:
        org_block = replace_once(org_block, '  String? _error;\\n', '  String? _error;\\n  int _loadEpoch = 0;\\n', 'Organizations epoch field')
        load_start = org_block.index('  Future<void> _load() async {')
        load_end = org_block.index('\\n  int _depth', load_start)
        load_block = org_block[load_start:load_end]
        load_block = replace_once(load_block, '  Future<void> _load() async {\\n    try {\\n', '  Future<void> _load() async {\\n    final epoch = ++_loadEpoch;\\n    try {\\n', 'Organizations epoch start')
        load_block = replace_once(load_block, '      if (!mounted) return;\\n      setState(() {\\n', '      if (!mounted || epoch != _loadEpoch) return;\\n      setState(() {\\n', 'Organizations stale success')
        load_block = replace_once(load_block, '    } catch (e) {\\n      if (mounted) {\\n', '    } catch (e) {\\n      if (mounted && epoch == _loadEpoch) {\\n', 'Organizations stale error')
        org_block = org_block[:load_start] + load_block + org_block[load_end:]
        org_text = org_text[:org_start] + org_block + org_text[org_end:]
        p_orgs.write_text(org_text, encoding='utf-8')
"""
if old not in text:
    raise SystemExit('Organizations patch section not found in finalizer')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
Path(__file__).unlink()
