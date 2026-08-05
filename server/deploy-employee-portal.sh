#!/usr/bin/env bash
# Публикация закрытого портала сотрудников WesiOS.
#
# Запускается на сервере от wesios-deploy из GitHub Actions:
#
#   WESI_ARTIFACTS_DIR=/opt/pocketbase/pb_public/artifacts \
#   bash deploy-employee-portal.sh --from /tmp/wesi-portal
#
# Статика кладётся внутрь каталога артефактов, поэтому для первого запуска не
# нужна отдельная правка nginx. При стандартной конфигурации адрес:
#   https://api.wesi-inc.ru/artifacts/portal/
#
# Если WESI_PORTAL_DIR указывает на /opt/pocketbase/pb_public/portal, адрес
# будет короче: https://api.wesi-inc.ru/portal/

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

say "Устанавливаю защищённые маршруты PocketBase"
HOOK_SOURCE="$FROM/employee_portal.pb.js"
HOOK_INSTALLED=no

install_hook() {
  local prefix=("$@")
  "${prefix[@]}" mkdir -p "$HOOK_DIR"
  "${prefix[@]}" install -m 0644 "$HOOK_SOURCE" "$HOOK_DIR/employee_portal.pb.js"
}

if [[ -f "$HOOK_SOURCE" ]]; then
  if [[ -w "$HOOK_DIR" ]] || { [[ ! -e "$HOOK_DIR" ]] && [[ -w "$(dirname "$HOOK_DIR")" ]]; }; then
    install_hook
    HOOK_INSTALLED=yes
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    install_hook sudo
    HOOK_INSTALLED=yes
  else
    echo "ПРЕДУПРЕЖДЕНИЕ: нет прав записи в $HOOK_DIR."
    echo "Портал работает, но до установки hook загрузка использует старый публичный путь."
    echo "Один раз от root:"
    echo "  install -d -o $(id -un) -g pocketbase '$HOOK_DIR'"
    echo "  install -m 0644 '$HOOK_SOURCE' '$HOOK_DIR/employee_portal.pb.js'"
  fi
else
  echo "ПРЕДУПРЕЖДЕНИЕ: employee_portal.pb.js не передан."
fi

say "Проверяю опубликованное"
test -s "$PORTAL_DIR/index.html"
test -s "$PORTAL_DIR/styles.css"
test -s "$PORTAL_DIR/app.js"

printf 'Портал: %s\n' "$PORTAL_DIR"
printf 'PocketBase hook: %s\n' "$HOOK_INSTALLED"
printf 'Размеры:\n'
wc -c "$PORTAL_DIR"/*

if [[ "$PORTAL_DIR" == */pb_public/portal ]]; then
  echo "Ожидаемый URL: https://api.wesi-inc.ru/portal/"
elif [[ "$PORTAL_DIR" == */artifacts/portal ]]; then
  echo "Ожидаемый URL: https://api.wesi-inc.ru/artifacts/portal/"
else
  echo "URL зависит от конфигурации раздачи каталога: $PORTAL_DIR"
fi
