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
# Что здесь важно и почему.
#
# **Манифест пишется последним и подменяется одним движением.** Приложение
# читает манифест и по нему идёт за файлом. Если манифест обновить раньше
# файлов — или дописывать его на месте, — найдётся телефон, который прочитает
# его ровно в эту секунду и пойдёт за версией, которой ещё нет. `mv` внутри
# одной файловой системы атомарен: читатель видит либо старый манифест
# целиком, либо новый целиком, и никогда — половину.
#
# **Старое удаляется только после того, как новое встало.** Порядок обратный
# — и неудачная выкладка оставляет сервер вообще без сборок.
#
# **Считаем sha256.** Размер файла ловит обрыв закачки, но не подмену и не
# тихую порчу. Раз сервер становится единственным источником приложений,
# проверять целостность обязан клиент, а для этого ему нужна контрольная
# сумма из манифеста.

set -euo pipefail

# Куда класть.
#
# **Два места, и второе проще.**
#
# `/srv/wesi-artifacts` — отдельный каталог, но его надо кому-то отдавать
# наружу: блок `location /artifacts/` в nginx, правка конфига, `nginx -t`,
# перезагрузка. Всё это требует root.
#
# `pb_public` внутри PocketBase — каталог, который PocketBase раздаёт сам,
# по тем же адресам и по тому же сертификату. Ни строчки в nginx, ни root:
# достаточно права записи у того пользователя, под которым идёт выкладка.
# Проверяется одним запросом — если сервер отвечает
# `{"message":"File not found."}`, значит статический обработчик PocketBase
# работает и файлы из pb_public он отдаст.
#
#   WESI_ARTIFACTS=/opt/pocketbase/pb_public/artifacts bash deploy-artifact.sh ...
#
# Адрес получается один и тот же: https://ДОМЕН/artifacts/app/...
ROOT="${WESI_ARTIFACTS:-/srv/wesi-artifacts}"
APP_DIR="$ROOT/app"

VERSION=""; BUILD=""; FROM=""; NOTES=""; KEEP=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build)   BUILD="$2";   shift 2 ;;
    --from)    FROM="$2";    shift 2 ;;
    --notes)   NOTES="$2";   shift 2 ;;
    # Текст в base64. Так его можно безопасно передать по SSH: в командной
    # строке оказываются только буквы и цифры, и никакие кавычки, точки с
    # запятой и обратные апострофы внутри описания не превращаются в
    # команды на этом сервере.
    --notes-b64) NOTES="$(printf '%s' "$2" | base64 -d)"; shift 2 ;;
    --keep)    KEEP="$2";    shift 2 ;;
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

# ------------------------------------------------------------ что приехало

WIN="wesios-windows-x64.zip"
APK="wesios-android.apk"

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
# Половина выкладки хуже отсутствия выкладки: на одной платформе обновление
# появится, на другой манифест будет обещать файл, которого нет.
[[ "$MISSING" == "0" ]] || { echo "Выкладка отменена." >&2; exit 1; }

# ------------------------------------------------------------- раскладка

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

# --------------------------------------------------------------- манифест

say "Пишу манифест"
TMP="$APP_DIR/.app-manifest.json.$$"

# Пути в манифесте относительные. Домен подставляет приложение — так один и
# тот же манифест годится и для api.wesi-inc.ru, и для проверки с другого
# адреса, и для локальной отладки.
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

# Проверяем, что получился разбираемый JSON, ДО того как он станет текущим.
# Битый манифест ломает обновление у всех разом, и чинится это только руками.
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP" || {
  echo "Манифест получился нечитаемым — не подменяю." >&2
  rm -f "$TMP"; exit 1; }

chmod 0644 "$TMP"
mv -f "$TMP" "$APP_DIR/app-manifest.json"
printf '    app-manifest.json обновлён\n'

# ---------------------------------------------------------------- уборка

# Удаляем только ПОСЛЕ того, как новая версия встала и манифест на неё
# показывает. И оставляем несколько прошлых: откатиться должно быть куда.
say "Убираю старые версии (оставляю текущую и $KEEP предыдущих)"

# Сначала отбираем только каталоги-версии, и лишь потом считаем, сколько
# оставить. Наоборот — и посторонний каталог рядом (чья-нибудь резервная
# копия) занимает место в «оставляем», а настоящая версия из-за него
# удаляется. Поймано на проверке.
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
    # Пояс и подтяжки: удаляем только внутри каталога сборок. Ошибка в этой
    # строке стоит всего сервера.
    case "$d" in
      "$APP_DIR"/*) rm -rf -- "$d"; printf '    удалено %s\n' "$(basename "$d")" ;;
      *)            printf '    пропускаю (вне каталога сборок): %s\n' "$d" ;;
    esac
  done
fi

say "Готово: $RELEASE"
ls -la "$APP_DIR"
