from pathlib import Path


def replace_once_if_needed(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old!r}')
    p.write_text(text.replace(old, new, 1))


# The deploy script is the source of truth for which PocketBase hooks are
# actually installed on production.
replace_once_if_needed(
    'server/deploy-employee-portal.sh',
    '  wesi_sync_context.pb.js wesi_sync_read.pb.js wesi_sync_write.pb.js \\\n  wesi_sysadmin.pb.js; do',
    '  wesi_sync_context.pb.js wesi_sync_read.pb.js wesi_sync_write.pb.js \\\n  wesi_sync_extra.pb.js wesi_sysadmin.pb.js; do',
)
replace_once_if_needed(
    'server/deploy-employee-portal.sh',
    '  "$FROM/wesi_sync_write.pb.js"\n  "$FROM/wesi_sysadmin.pb.js"',
    '  "$FROM/wesi_sync_write.pb.js"\n  "$FROM/wesi_sync_extra.pb.js"\n  "$FROM/wesi_sysadmin.pb.js"',
)

# Wire the extra hook into the permanent employee-portal deployment workflow:
# trigger, validation, syntax check, upload and production route verification.
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
    replace_once_if_needed('.github/workflows/deploy-employee-portal.yml', old, new)
