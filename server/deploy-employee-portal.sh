#!/usr/bin/env bash
# Публикация закрытого портала сотрудников WesiOS.
#
# Запускается на сервере от wesios-deploy из GitHub Actions:
#
#   WESI_ARTIFACTS_DIR=/opt/pocketbase/pb_public/artifacts \
#   bash deploy-employee-portal.sh --from /tmp/wesi-portal
#
# Статика кладётся внутрь каталога артефактов, куда deploy-пользователь уже
# умеет писать. PocketBase hook публикует этот каталог по красивому адресу:
#   https://api.wesi-inc.ru/portal/
#
# Пока hook ещё не установлен, остаётся технический запасной адрес:
#   https://api.wesi-inc.ru/artifacts/portal/

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
[[ -f "$FROM/index.html" && -f "$FROM/styles.css" && -f "$FROM/app.js" ]] || {
  echo "В $FROM нет полного портала (index.html/styles.css/app.js)" >&2
  exit 2
}

say() { printf '\n==> %s\n' "$1"; }

say "Проверяю файлы портала"
python3 - "$FROM" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ("index.html", "styles.css", "app.js"):
    p = root / name
    if not p.is_file() or p.stat().st_size < 100:
        raise SystemExit(f"{name}: файл отсутствует или подозрительно мал")
html = (root / "index.html").read_text(encoding="utf-8")
if "WesiOS" not in html or "app.js" not in html or "styles.css" not in html:
    raise SystemExit("index.html не похож на портал WesiOS")
print("Файлы портала выглядят целыми")
PY

say "Публикую статику атомарно"
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

# Сначала готовим полный новый каталог и только потом меняем текущий. При
# обрыве копирования сотрудник увидит прежний портал, а не половину нового.
rm -rf "$BACKUP"
if [[ -d "$PORTAL_DIR" ]]; then mv "$PORTAL_DIR" "$BACKUP"; fi
mv "$STAGE" "$PORTAL_DIR"
rm -rf "$BACKUP"

say "Устанавливаю маршруты PocketBase"
HOOK_INSTALLED=no
HOOK_SOURCES=(
  "$FROM/employee_portal.pb.js"
  "$FROM/employee_portal_static.pb.js"
)

install_hooks() {
  local prefix=("$@")
  "${prefix[@]}" mkdir -p "$HOOK_DIR"
  local source
  for source in "${HOOK_SOURCES[@]}"; do
    [[ -f "$source" ]] || continue
    "${prefix[@]}" install -m 0644 "$source" "$HOOK_DIR/$(basename "$source")"
  done
}

FOUND_HOOK=no
for source in "${HOOK_SOURCES[@]}"; do
  [[ -f "$source" ]] && FOUND_HOOK=yes
done

if [[ "$FOUND_HOOK" == yes ]]; then
  if [[ -w "$HOOK_DIR" ]] || { [[ ! -e "$HOOK_DIR" ]] && [[ -w "$(dirname "$HOOK_DIR")" ]]; }; then
    install_hooks
    HOOK_INSTALLED=yes
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    install_hooks sudo
    HOOK_INSTALLED=yes
  else
    echo "ПРЕДУПРЕЖДЕНИЕ: нет прав записи в $HOOK_DIR."
    echo "Статика опубликована, но защищённые загрузки и адрес /portal/ не включены."
    echo "Один раз от root выполните:"
    echo "  install -d -o $(id -un) -g pocketbase '$HOOK_DIR'"
    for source in "${HOOK_SOURCES[@]}"; do
      [[ -f "$source" ]] || continue
      echo "  install -m 0644 '$source' '$HOOK_DIR/$(basename "$source")'"
    done
  fi
else
  echo "ПРЕДУПРЕЖДЕНИЕ: PocketBase hooks не переданы."
fi

say "Проверяю опубликованное"
test -s "$PORTAL_DIR/index.html"
test -s "$PORTAL_DIR/styles.css"
test -s "$PORTAL_DIR/app.js"

printf 'Портал: %s\n' "$PORTAL_DIR"
printf 'PocketBase hooks: %s\n' "$HOOK_INSTALLED"
printf 'Размеры:\n'
wc -c "$PORTAL_DIR"/*

echo "Основной URL после установки hooks: https://api.wesi-inc.ru/portal/"
echo "Запасной URL: https://api.wesi-inc.ru/artifacts/portal/"
