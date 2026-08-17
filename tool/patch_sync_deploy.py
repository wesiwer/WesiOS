from pathlib import Path


def add_after(path: str, anchor: str, addition: str) -> None:
    p = Path(path)
    text = p.read_text()
    if addition.strip() in text:
        return
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {anchor!r}')
    p.write_text(text.replace(anchor, anchor + addition, 1))


# The deploy script is the source of truth for which PocketBase hooks are
# actually installed on production.
p = Path('server/deploy-employee-portal.sh')
text = p.read_text()
text = text.replace(
    '  wesi_sync_context.pb.js wesi_sync_read.pb.js wesi_sync_write.pb.js \\\n  wesi_sysadmin.pb.js; do',
    '  wesi_sync_context.pb.js wesi_sync_read.pb.js wesi_sync_write.pb.js \\\n  wesi_sync_extra.pb.js wesi_sysadmin.pb.js; do',
    1,
)
text = text.replace(
    '  "$FROM/wesi_sync_write.pb.js"\n  "$FROM/wesi_sysadmin.pb.js"',
    '  "$FROM/wesi_sync_write.pb.js"\n  "$FROM/wesi_sync_extra.pb.js"\n  "$FROM/wesi_sysadmin.pb.js"',
    1,
)
p.write_text(text)

# Wire the extra hook into the permanent employee-portal deployment workflow:
# trigger, validation, syntax check, upload and production route verification.
p = Path('.github/workflows/deploy-employee-portal.yml')
text = p.read_text()
replacements = [
    (
        "      - 'server/pb_hooks/wesi_sync_write.pb.js'\n",
        "      - 'server/pb_hooks/wesi_sync_write.pb.js'\n      - 'server/pb_hooks/wesi_sync_extra.pb.js'\n",
    ),
    (
        '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n',
        '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sync_extra.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n',
    ),
    (
        '          node --check server/pb_hooks/wesi_sync_write.pb.js\n',
        '          node --check server/pb_hooks/wesi_sync_write.pb.js\n          node --check server/pb_hooks/wesi_sync_extra.pb.js\n',
    ),
    (
        "          grep -q 'vault_private' server/pb_hooks/wesi_sync_write.pb.js\n",
        "          grep -q 'vault_private' server/pb_hooks/wesi_sync_write.pb.js\n          grep -q '/api/wesi/sync/revision-v2' server/pb_hooks/wesi_sync_extra.pb.js\n          grep -q '/api/wesi/sync/sandbox_transactions' server/pb_hooks/wesi_sync_extra.pb.js\n",
    ),
    (
        '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n            server/deploy-employee-portal.sh \\\n',
        '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sync_extra.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n            server/deploy-employee-portal.sh \\\n',
    ),
    (
        '            /api/wesi/sync/revision; do\n',
        '            /api/wesi/sync/revision \\\n            /api/wesi/sync/revision-v2; do\n',
    ),
]
for old, new in replacements:
    if new in text:
        continue
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'deploy-employee-portal.yml: expected one match, got {count}: {old!r}')
    text = text.replace(old, new, 1)
p.write_text(text)
