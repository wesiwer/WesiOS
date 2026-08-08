#!/usr/bin/env bash
#
# Раскладывает присланную сборку по своим местам и делает её текущей.
#
# Запускается НА СЕРВЕРЕ, из GitHub Actions по SSH. Руками — только при
# разборе полётов.
#
#   bash deploy-artifact.sh --version 0.1.5 --build 12 \
#                           --from /tmp/wesios-upload \
#                           [--notes "Что нового"] [--keep 2]
#
# Манифест пишется последним и подменяется атомарно. Старые релизы удаляются
# только после успешной выкладки нового. Для каждого файла публикуются размер
# и SHA-256, чтобы клиент мог проверить целостность скачивания.

set -euo pipefail

# Production WesiOS уже работает из /opt/pocketbase, а PocketBase раздаёт
# pb_public напрямую. Поэтому это безопасный и реально используемый default.
# При отдельном nginx-хранилище путь по-прежнему можно переопределить через
# WESI_ARTIFACTS или --root.
ROOT="${WESI_ARTIFACTS:-/opt/pocketbase/pb_public/artifacts}"
APP_DIR="$ROOT/app"

VERSION=""; BUILD=""; FROM=""; NOTES=""; KEEP=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build)   BUILD="$2";   shift 2 ;;
    --from)    FROM="$2";    shift 2 ;;
    --notes)   NOTES="$2"; shift 2 ;;
    --notes-b64) NOTES="$(printf '%s' "$2" | base64 -d)"; shift 2 ;;
    --keep)    KEEP="$2"; shift 2 ;;
    --root)    ROOT="$2"; APP_DIR="$ROOT/app"; shift 2 ;;
    *) echo "Неизвестный ключ: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$VERSION" && -n "$BUILD" && -n "$FROM" ]] || {
  echo "Нужны --version, --build и --from" >&2; exit 1; }
[[ -d "$FROM" ]] || { echo "Нет каталога с файлами: $FROM" >&2; exit 1; }

say() { printf '\n==> %s\n' "$1"; }

RELEASE="$VERSION+$BUILD"
TARGET="$APP_DIR/$RELEASE"
APK="wesios-android.apk"

# Windows release исторически существовал в двух видах. Старый server deploy
# ожидал setup.exe, а текущий release-app публикует portable ZIP. Принимаем
# оба, но в манифест пишем именно тот файл, который реально пришёл.
if [[ -s "$FROM/wesios-windows-x64-setup.exe" ]]; then
  WIN="wesios-windows-x64-setup.exe"
elif [[ -s "$FROM/wesios-windows-x64.zip" ]]; then
  WIN="wesios-windows-x64.zip"
else
  WIN="wesios-windows-x64.zip"
fi

say "Проверяю присланное"
MISSING=0
for f in "$WIN" "$APK"; do
  if [[ -s "$FROM/$f" ]]; then
    printf '    %s — %s байт\n' "$f" "$(stat -c%s "$FROM/$f")"
  else
    printf '    НЕТ ИЛИ ПУСТО: %s\n' "$f" >&2
    MISSING=1
  fi
done
[[ "$MISSING" == "0" ]] || { echo "Выкладка отменена." >&2; exit 1; }

say "Кладу в $TARGET"
mkdir -p "$TARGET"
install -m 0644 "$FROM/$WIN" "$TARGET/$WIN"
install -m 0644 "$FROM/$APK" "$TARGET/$APK"

sha() { sha256sum "$1" | awk '{print $1}'; }
WIN_SHA="$(sha "$TARGET/$WIN")"
APK_SHA="$(sha "$TARGET/$APK")"
WIN_SIZE="$(stat -c%s "$TARGET/$WIN")"
APK_SIZE="$(stat -c%s "$TARGET/$APK")"

printf '    windows sha256 %s\n' "$WIN_SHA"
printf '    android sha256 %s\n' "$APK_SHA"

say "Пишу манифест"
TMP="$APP_DIR/.app-manifest.json.$$"

cat > "$TMP" <<JSON
{
  "version": "$VERSION",
  "build": $BUILD,
  "publishedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "windows": {
    "version": "$VERSION",
    "build": $BUILD,
    "asset": "$WIN",
    "path": "app/$RELEASE/$WIN",
    "sizeBytes": $WIN_SIZE,
    "sha256": "$WIN_SHA",
    "notes": $( [[ -n "$NOTES" ]] && printf '%s' "$NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' || printf 'null' )
  },
  "android": {
    "version": "$VERSION",
    "build": $BUILD,
    "asset": "$APK",
    "path": "app/$RELEASE/$APK",
    "sizeBytes": $APK_SIZE,
    "sha256": "$APK_SHA",
    "notes": $( [[ -n "$NOTES" ]] && printf '%s' "$NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' || printf 'null' )
  }
}
JSON

python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP" || {
  echo "Манифест получился нечитаемым — не подменяю." >&2
  rm -f "$TMP"; exit 1; }

chmod 0644 "$TMP"
mv -f "$TMP" "$APP_DIR/app-manifest.json"
printf '    app-manifest.json обновлён\n'

say "Убираю старые версии (оставляю текущую и $KEEP предыдущих)"
VERSIONS=()
while IFS= read -r -d '' d; do
  [[ "$(basename "$d")" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || continue
  VERSIONS+=("$d")
done < <(find "$APP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\0' \
           | sort -zrn | sed -z 's/^[^\t]*\t//')

OLD=("${VERSIONS[@]:$((KEEP + 1))}")
if [[ "${#OLD[@]}" -eq 0 ]]; then
  printf '    нечего убирать\n'
else
  for d in "${OLD[@]}"; do
    case "$d" in
      "$APP_DIR"/*) rm -rf -- "$d"; printf '    удалено %s\n' "$(basename "$d")" ;;
      *)            printf '    пропускаю (вне каталога сборок): %s\n' "$d" ;;
    esac
  done
fi

say "Готово: $RELEASE"
ls -la "$APP_DIR"
