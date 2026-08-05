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
for file in index.html styles.css app.js app_icon.png; do
  [[ -s "$FROM/$file" ]] || { echo "Нет файла $FROM/$file" >&2; exit 2; }
done

PARENT="$(dirname "$PORTAL_DIR")"
NAME="$(basename "$PORTAL_DIR")"
STAGE="$PARENT/.${NAME}.stage.$$"
BACKUP="$PARENT/.${NAME}.previous"
mkdir -p "$PARENT"
rm -rf "$STAGE"
mkdir -p "$STAGE"
install -m 0644 "$FROM/index.html" "$STAGE/index.html"
install -m 0644 "$FROM/styles.css" "$STAGE/styles.css"
install -m 0644 "$FROM/app.js" "$STAGE/app.js"
install -m 0644 "$FROM/app_icon.png" "$STAGE/app_icon.png"
rm -rf "$BACKUP"
if [[ -d "$PORTAL_DIR" ]]; then mv "$PORTAL_DIR" "$BACKUP"; fi
mv "$STAGE" "$PORTAL_DIR"
rm -rf "$BACKUP"

HOOK_SOURCES=("$FROM/employee_portal.pb.js" "$FROM/employee_portal_static.pb.js")
install_hooks() {
  local prefix=("$@")
  "${prefix[@]}" mkdir -p "$HOOK_DIR"
  local source
  for source in "${HOOK_SOURCES[@]}"; do
    [[ -f "$source" ]] || continue
    "${prefix[@]}" install -m 0644 "$source" "$HOOK_DIR/$(basename "$source")"
  done
}

if [[ -w "$HOOK_DIR" ]] || { [[ ! -e "$HOOK_DIR" ]] && [[ -w "$(dirname "$HOOK_DIR")" ]]; }; then
  install_hooks
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  install_hooks sudo
else
  echo "ПРЕДУПРЕЖДЕНИЕ: hooks не обновлены из-за прав" >&2
fi

test -s "$PORTAL_DIR/index.html"
test -s "$PORTAL_DIR/app_icon.png"
printf 'Портал опубликован: %s\n' "$PORTAL_DIR"
printf 'Основной URL: https://api.wesi-inc.ru/portal/\n'
