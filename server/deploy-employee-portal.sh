#!/usr/bin/env bash
set -euo pipefail

FROM=""
ARTIFACTS_ROOT="${WESI_ARTIFACTS_DIR:-${WESI_ARTIFACTS:-/opt/pocketbase/pb_public/artifacts}}"
PORTAL_DIR="${WESI_PORTAL_DIR:-$ARTIFACTS_ROOT/portal}"
HOOK_DIR="${WESI_PB_HOOK_DIR:-/opt/pocketbase/pb_hooks}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --portal-dir) PORTAL_DIR="$2"; shift 2 ;;
    --hook-dir) HOOK_DIR="$2"; shift 2 ;;
    *) echo "Неизвестный параметр: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$FROM" ]] || { echo "Нужен --from" >&2; exit 2; }
for file in index.html styles.css portal-v6.css app.js motion-v6.js app_icon.png \
  employee_portal.pb.js employee_portal_static.pb.js wesi_security.pb.js \
  wesi_auth_bootstrap.pb.js wesi_mail_health.pb.js \
  wesi_sync_context.pb.js wesi_sync_read.pb.js wesi_sync_write.pb.js; do
  [[ -s "$FROM/$file" ]] || { echo "Нет файла $FROM/$file" >&2; exit 2; }
done

PARENT="$(dirname "$PORTAL_DIR")"
NAME="$(basename "$PORTAL_DIR")"
STAGE="$PARENT/.${NAME}.stage.$$"
BACKUP="$PARENT/.${NAME}.previous"
mkdir -p "$PARENT"
rm -rf "$STAGE"
mkdir -p "$STAGE"

python3 - "$FROM" "$STAGE/index.html" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
out = Path(sys.argv[2])
html = (root / "index.html").read_text(encoding="utf-8")
styles = (root / "styles.css").read_text(encoding="utf-8")
portal_styles = (root / "portal-v6.css").read_text(encoding="utf-8")
app_js = (root / "app.js").read_text(encoding="utf-8").replace("</script", "<\\/script")
motion_js = (root / "motion-v6.js").read_text(encoding="utf-8").replace("</script", "<\\/script")

def inline(pattern, replacement, source):
    return re.subn(pattern, lambda _: replacement, source, count=1)

html, n1 = inline(
    r'<link\s+rel="stylesheet"\s+href="\./styles\.css[^"]*"\s*/?>',
    '<style data-bundle="styles.css">\n' + styles + '\n</style>', html)
html, n2 = inline(
    r'<link\s+rel="stylesheet"\s+href="\./portal-v6\.css[^"]*"\s*/?>',
    '<style data-bundle="portal-v6.css">\n' + portal_styles + '\n</style>', html)
html, n3 = inline(
    r'<script\s+src="\./app\.js[^"]*"\s+defer></script>',
    '<script data-bundle="app.js">\n' + app_js + '\n</script>', html)
html, n4 = inline(
    r'<script\s+src="\./motion-v6\.js[^"]*"\s+defer></script>',
    '<script data-bundle="motion-v6.js">\n' + motion_js + '\n</script>', html)

if (n1, n2, n3, n4) != (1, 1, 1, 1):
    raise SystemExit(f"Не удалось собрать портал: replacements={(n1, n2, n3, n4)}")

html = html.replace(
    '</head>',
    '<style>html,body{background:var(--bg,#08080b);color:var(--text,#f7f7f8)}'
    '.boot-failsafe .app-shell{visibility:visible!important;opacity:1!important}</style>'
    '<script>(function(){setTimeout(function(){var r=document.documentElement;'
    'if(r.classList.contains("is-booting")){r.classList.remove("is-booting");'
    'r.classList.add("is-ready","boot-failsafe")}},3200)})();</script>'
    '</head>', 1)

out.write_text(html, encoding="utf-8")
print(f"Bundled portal size: {out.stat().st_size} bytes")
PY

for file in styles.css portal-v6.css app.js motion-v6.js app_icon.png; do
  install -m 0644 "$FROM/$file" "$STAGE/$file"
done

test -s "$STAGE/index.html"
grep -q 'data-bundle="styles.css"' "$STAGE/index.html"
grep -q 'data-bundle="app.js"' "$STAGE/index.html"
[[ "$(wc -c < "$STAGE/index.html")" -gt 25000 ]] || {
  echo "Собранный index.html подозрительно мал" >&2
  exit 2
}

rm -rf "$BACKUP"
if [[ -d "$PORTAL_DIR" ]]; then mv "$PORTAL_DIR" "$BACKUP"; fi
mv "$STAGE" "$PORTAL_DIR"
rm -rf "$BACKUP"

HOOK_SOURCES=(
  "$FROM/employee_portal.pb.js"
  "$FROM/employee_portal_static.pb.js"
  "$FROM/wesi_security.pb.js"
  "$FROM/wesi_auth_bootstrap.pb.js"
  "$FROM/wesi_mail_health.pb.js"
  "$FROM/wesi_sync_context.pb.js"
  "$FROM/wesi_sync_read.pb.js"
  "$FROM/wesi_sync_write.pb.js"
)
HOOK_MODE=""

all_existing_hooks_writable() {
  local source target
  for source in "${HOOK_SOURCES[@]}"; do
    target="$HOOK_DIR/$(basename "$source")"
    [[ -f "$target" && -w "$target" ]] || return 1
  done
}

write_existing_hooks() {
  local source target
  for source in "${HOOK_SOURCES[@]}"; do
    target="$HOOK_DIR/$(basename "$source")"
    cat "$source" > "$target"
    chmod 0644 "$target"
  done
}

install_hooks() {
  local prefix=("$@")
  "${prefix[@]}" mkdir -p "$HOOK_DIR"
  local source
  for source in "${HOOK_SOURCES[@]}"; do
    "${prefix[@]}" install -m 0644 "$source" "$HOOK_DIR/$(basename "$source")"
  done
}

if all_existing_hooks_writable; then
  write_existing_hooks
  HOOK_MODE="existing-files"
elif [[ -w "$HOOK_DIR" ]] || {
  [[ ! -e "$HOOK_DIR" ]] && [[ -w "$(dirname "$HOOK_DIR")" ]]
}; then
  install_hooks
  HOOK_MODE="direct"
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  install_hooks sudo
  HOOK_MODE="sudo"
else
  echo "ОШИБКА: нет прав обновить PocketBase hooks в $HOOK_DIR." >&2
  echo "Нужна запись либо в существующие hook-файлы, либо в каталог pb_hooks." >&2
  exit 3
fi

for source in "${HOOK_SOURCES[@]}"; do
  target="$HOOK_DIR/$(basename "$source")"
  if [[ "$HOOK_MODE" == "sudo" ]]; then
    sudo -n cmp -s "$source" "$target" || {
      echo "ОШИБКА: установленный hook не совпадает: $target" >&2
      exit 3
    }
  else
    cmp -s "$source" "$target" || {
      echo "ОШИБКА: установленный hook не совпадает: $target" >&2
      exit 3
    }
  fi
  printf 'PocketBase hook подтверждён: %s (%s)\n' "$target" "$HOOK_MODE"
done

sleep 2

test -s "$PORTAL_DIR/index.html"
test -s "$PORTAL_DIR/app_icon.png"
printf 'Портал опубликован: %s\n' "$PORTAL_DIR"
printf 'Основной URL: https://api.wesi-inc.ru/portal/\n'
