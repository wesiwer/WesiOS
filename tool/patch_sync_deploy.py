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


def replace_all_if_needed(path: str, old: str, new: str, expected: int) -> None:
    p = Path(path)
    text = p.read_text()
    # If every relevant block is already patched, there is nothing to do.
    if text.count(new) >= expected:
        return
    count = text.count(old)
    if count != expected:
        raise SystemExit(
            f'{path}: expected {expected} anchors, got {count}: {old!r}'
        )
    p.write_text(text.replace(old, new))


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

# Wire the extra hook into the permanent employee-portal deployment workflow.
replace_once_if_needed(
    '.github/workflows/deploy-employee-portal.yml',
    "      - 'server/pb_hooks/wesi_sync_write.pb.js'\n",
    "      - 'server/pb_hooks/wesi_sync_write.pb.js'\n      - 'server/pb_hooks/wesi_sync_extra.pb.js'\n",
)

# The same adjacent hook pair appears in the validation file list and in SCP;
# both must contain the extra hook.
replace_all_if_needed(
    '.github/workflows/deploy-employee-portal.yml',
    '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n',
    '            server/pb_hooks/wesi_sync_write.pb.js \\\n            server/pb_hooks/wesi_sync_extra.pb.js \\\n            server/pb_hooks/wesi_sysadmin.pb.js \\\n',
    2,
)
replace_once_if_needed(
    '.github/workflows/deploy-employee-portal.yml',
    '          node --check server/pb_hooks/wesi_sync_write.pb.js\n',
    '          node --check server/pb_hooks/wesi_sync_write.pb.js\n          node --check server/pb_hooks/wesi_sync_extra.pb.js\n',
)
replace_once_if_needed(
    '.github/workflows/deploy-employee-portal.yml',
    "          grep -q 'vault_private' server/pb_hooks/wesi_sync_write.pb.js\n",
    "          grep -q 'vault_private' server/pb_hooks/wesi_sync_write.pb.js\n          grep -q '/api/wesi/sync/revision-v2' server/pb_hooks/wesi_sync_extra.pb.js\n          grep -q '/api/wesi/sync/sandbox_transactions' server/pb_hooks/wesi_sync_extra.pb.js\n",
)
replace_once_if_needed(
    '.github/workflows/deploy-employee-portal.yml',
    '            /api/wesi/sync/revision; do\n',
    '            /api/wesi/sync/revision \\\n            /api/wesi/sync/revision-v2; do\n',
)
