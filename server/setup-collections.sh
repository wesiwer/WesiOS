#!/usr/bin/env bash
#
# Создаёт в PocketBase всё, что нужно WesiOS: коллекцию, индекс, правила
# доступа и учётную запись для входа из приложения.
#
# Раньше это была страница инструкций «зайдите в панель и создайте шесть
# полей». Ошибиться там легко, а ошибка выглядит как «синхронизация молча не
# работает» — самый неприятный вид поломки. Поэтому теперь скриптом.
#
# ЗАПУСК на сервере, после install-sync.sh:
#
#   bash setup-collections.sh --admin ПОЧТА --admin-pass ПАРОЛЬ \
#                             --user ПОЧТА  --user-pass ПАРОЛЬ
#
# Первая пара — администратор PocketBase (создаётся, если его ещё нет).
# Вторая — та учётная запись, которую вы введёте в приложении.
#
# Повторный запуск ничего не ломает: существующее не пересоздаётся.

set -euo pipefail

HOST="${HOST:-http://127.0.0.1:8090}"
PB_BIN="${PB_BIN:-/opt/pocketbase/pocketbase}"
PB_DATA="${PB_DATA:-/opt/pocketbase/pb_data}"
COLLECTION="wesios_records"

ADMIN=""; ADMIN_PASS=""; APP_USER=""; APP_PASS=""; ONLY_RULES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin)      ADMIN="$2"; shift 2 ;;
    --admin-pass) ADMIN_PASS="$2"; shift 2 ;;
    --user)       APP_USER="$2"; shift 2 ;;
    --user-pass)  APP_PASS="$2"; shift 2 ;;
    --host)       HOST="$2"; shift 2 ;;
    # Только права доступа: ничего не создаёт, ничего не заводит. Для
    # случая «сервер уже работает, надо срочно закрыть данные».
    --only-rules) ONLY_RULES=1; shift ;;
    *) echo "Неизвестный ключ: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ADMIN" || -z "$ADMIN_PASS" ]]; then
  echo "Нужны --admin и --admin-pass" >&2
  exit 1
fi

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m%s\033[0m\n' "$1"; }
warn() { printf '    \033[0;33m%s\033[0m\n' "$1"; }

command -v curl >/dev/null || { echo "Нужен curl" >&2; exit 1; }
command -v jq   >/dev/null || { apt-get update -qq && apt-get install -y -qq jq; }

# ------------------------------------------------------- администратор

say "Проверяю администратора"
# В разных версиях PocketBase команда называется по-разному: до 0.23 это
# `admin create`, начиная с 0.23 — `superuser create`. Пробуем обе и не
# считаем ошибкой, если администратор уже есть.
if [[ "$ONLY_RULES" == "1" ]]; then
  warn "--only-rules: администратора не трогаю"
elif "$PB_BIN" superuser create "$ADMIN" "$ADMIN_PASS" --dir "$PB_DATA" 2>/dev/null; then
  ok "Администратор создан (superuser)"
elif "$PB_BIN" admin create "$ADMIN" "$ADMIN_PASS" --dir "$PB_DATA" 2>/dev/null; then
  ok "Администратор создан (admin)"
else
  warn "Администратор уже существует или создаётся иначе — продолжаю"
fi

say "Вхожу как администратор"
TOKEN=""
for path in \
  "/api/collections/_superusers/auth-with-password" \
  "/api/admins/auth-with-password"
do
  RESP="$(curl -sS -X POST "$HOST$path" \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":\"$ADMIN\",\"password\":\"$ADMIN_PASS\"}" || true)"
  TOKEN="$(printf '%s' "$RESP" | jq -r '.token // empty')"
  [[ -n "$TOKEN" ]] && break
done

if [[ -z "$TOKEN" ]]; then
  echo "Не удалось войти администратором. Ответ сервера:" >&2
  printf '%s\n' "$RESP" >&2
  echo "Пришлите этот ответ — по нему видно, что именно не сошлось." >&2
  exit 1
fi
ok "Вошёл"

AUTH=(-H "Authorization: $TOKEN")

# ---------------------------------------------------------- коллекция

say "Создаю коллекцию $COLLECTION"

# Поле org есть с самого начала, хотя правила пока им не пользуются.
# Добавить поле в коллекцию с данными потом — это миграция; добавить сейчас
# — ничего не стоит. Через него пойдёт общий доступ сотрудников.
#
# stamp — текст, а не дата: у типа Date в PocketBase свой формат и своя
# точность, и приложение сравнивало бы не то, что записало.
SCHEMA='{
  "name": "'"$COLLECTION"'",
  "type": "base",
  "listRule":   "owner = @request.auth.id",
  "viewRule":   "owner = @request.auth.id",
  "createRule": "owner = @request.auth.id",
  "updateRule": "owner = @request.auth.id",
  "deleteRule": "owner = @request.auth.id",
  "indexes": [
    "CREATE UNIQUE INDEX idx_wesios_rid ON '"$COLLECTION"' (owner, coll, rid)"
  ],
  "fields": [
    {"name":"owner","type":"text","required":true},
    {"name":"org","type":"text","required":false},
    {"name":"coll","type":"text","required":true},
    {"name":"rid","type":"text","required":true},
    {"name":"payload","type":"json","required":false,"maxSize":2000000},
    {"name":"stamp","type":"text","required":true},
    {"name":"deleted","type":"bool","required":false}
  ]
}'

EXISTS="$(curl -sS "${AUTH[@]}" "$HOST/api/collections/$COLLECTION" \
  | jq -r '.id // empty' || true)"

if [[ -n "$EXISTS" ]]; then
  # Раньше здесь стояло «уже есть — не трогаю», и это оказалось дырой.
  #
  # Коллекцию можно создать руками в панели, и тогда правила доступа
  # останутся пустыми — а пустое правило в PocketBase означает не «никому»,
  # а «всем, включая неавторизованных». На живом сервере так и вышло: любой
  # человек в интернете мог прочитать и дописать записи. Снаружи это
  # выглядит совершенно нормально работающим сервером, поэтому само по себе
  # не обнаруживается никогда.
  #
  # Теперь права приводятся к нужным при каждом запуске. Поля и индексы не
  # трогаем — их правка на коллекции с данными это уже миграция.
  say "Коллекция есть — привожу права доступа к нужным"
  RULES='{
    "listRule":   "owner = @request.auth.id",
    "viewRule":   "owner = @request.auth.id",
    "createRule": "owner = @request.auth.id",
    "updateRule": "owner = @request.auth.id",
    "deleteRule": "owner = @request.auth.id"
  }'
  RESP="$(curl -sS -X PATCH "$HOST/api/collections/$EXISTS" "${AUTH[@]}" \
    -H 'Content-Type: application/json' -d "$RULES" || true)"
  if [[ -n "$(printf '%s' "$RESP" | jq -r '.id // empty')" ]]; then
    ok "Права: только владелец записи"
  else
    echo "Не удалось выставить права. Ответ сервера:" >&2
    printf '%s\n' "$RESP" >&2
    exit 1
  fi
else
  RESP="$(curl -sS -X POST "$HOST/api/collections" "${AUTH[@]}" \
    -H 'Content-Type: application/json' -d "$SCHEMA" || true)"
  if [[ -n "$(printf '%s' "$RESP" | jq -r '.id // empty')" ]]; then
    ok "Коллекция создана"
  else
    # Схема полей в PocketBase 0.22 называлась schema, а не fields.
    ALT="${SCHEMA/\"fields\":/\"schema\":}"
    RESP2="$(curl -sS -X POST "$HOST/api/collections" "${AUTH[@]}" \
      -H 'Content-Type: application/json' -d "$ALT" || true)"
    if [[ -n "$(printf '%s' "$RESP2" | jq -r '.id // empty')" ]]; then
      ok "Коллекция создана (старый формат схемы)"
    else
      echo "Не удалось создать коллекцию. Ответы сервера:" >&2
      printf '%s\n---\n%s\n' "$RESP" "$RESP2" >&2
      echo "Пришлите их — по ним видно, какая версия PocketBase и что не сошлось." >&2
      exit 1
    fi
  fi
fi

# --------------------------------------------------------- люди (users)

# Встроенная коллекция users приезжает с открытым списком: кто угодно может
# запросить перечень и увидеть почты всех сотрудников. Плюс открытая
# регистрация — посторонний заводит себе учётку сам.
#
# Ставим: видеть себя, менять себя, заводить — только администратору.
say "Закрываю коллекцию users"
USERS_ID="$(curl -sS "${AUTH[@]}" "$HOST/api/collections/users" \
  | jq -r '.id // empty' || true)"
if [[ -n "$USERS_ID" ]]; then
  # createRule: null — «только администратор». Пустая строка означала бы
  # обратное: «кто угодно», и это ровно та ошибка, ради которой всё это.
  RESP="$(curl -sS -X PATCH "$HOST/api/collections/$USERS_ID" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"listRule":"id = @request.auth.id","viewRule":"id = @request.auth.id","createRule":null,"updateRule":"id = @request.auth.id","deleteRule":null}' || true)"
  if [[ -n "$(printf '%s' "$RESP" | jq -r '.id // empty')" ]]; then
    ok "users: каждый видит только себя, регистрация закрыта"
  else
    warn "Не удалось: $(printf '%s' "$RESP" | head -c 200)"
  fi
else
  warn "Коллекции users нет — пропускаю"
fi

# ------------------------------------------------------ учётная запись

if [[ "$ONLY_RULES" == "1" ]]; then
  warn "--only-rules: учётную запись не трогаю"
elif [[ -n "$APP_USER" && -n "$APP_PASS" ]]; then
  say "Завожу учётную запись для приложения"
  RESP="$(curl -sS -X POST "$HOST/api/collections/users/records" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$APP_USER\",\"password\":\"$APP_PASS\",\"passwordConfirm\":\"$APP_PASS\",\"emailVisibility\":false,\"verified\":true}" || true)"
  if [[ -n "$(printf '%s' "$RESP" | jq -r '.id // empty')" ]]; then
    ok "Создана: $APP_USER"
  else
    warn "Не создана (возможно, уже есть). Ответ: $(printf '%s' "$RESP" | head -c 200)"
  fi
fi

# ------------------------------------------------------------- проверка

say "Проверяю, что снаружи всё отвечает"
HEALTH="$(curl -sS "$HOST/api/health" || true)"
printf '    %s\n' "$(printf '%s' "$HEALTH" | head -c 200)"

# ------------------------------------------------- проверка на посторонних
#
# Главная проверка этого скрипта, и она обязана быть последней и обязана
# ронять его при неудаче.
#
# Сервер с открытыми правами снаружи выглядит идеально: он отвечает, панель
# открывается, приложение синхронизируется. Единственный способ заметить
# дыру — специально сходить БЕЗ пропуска и убедиться, что не пустили.
# Именно этой проверки здесь не хватало, и именно поэтому коллекция,
# созданная руками в панели, полгода могла бы стоять нараспашку.
say "Стучусь без пропуска — должны не пустить"
LEAK=0

probe() { # $1 — что проверяем, $2 — путь, $3 — метод (по умолчанию GET)
  local code method args
  method="${3:-GET}"
  # Массив, а не строка: подстановка со скрытыми кавычками разъезжается по
  # словам, и curl получает «-H» отдельно от заголовка.
  args=(-sS -o /dev/null -w '%{http_code}' -X "$method")
  if [[ "$method" != "GET" ]]; then
    args+=(-H 'Content-Type: application/json' -d '{}')
  fi
  code="$(curl "${args[@]}" "$HOST$2" || echo 000)"
  # 400 при записи — это «правило пустило, не понравилось тело». Такой же
  # провал, как и 200.
  if [[ "$code" == "200" || "$code" == "400" ]]; then
    printf '    \033[0;31mОТКРЫТО: %s (HTTP %s)\033[0m\n' "$1" "$code"
    LEAK=1
  else
    ok "закрыто: $1 (HTTP $code)"
  fi
}

probe "чтение записей"        "/api/collections/$COLLECTION/records"
probe "запись записей"        "/api/collections/$COLLECTION/records" POST
probe "список пользователей"  "/api/collections/users/records"

if [[ "$LEAK" == "1" ]]; then
  cat >&2 <<'BAD'

================ ОСТАНОВИЛСЯ ================

Часть данных доступна без входа. Это не мелочь: любой, кто знает адрес,
читает и дописывает записи компании.

Пустое правило в PocketBase означает «всем», а не «никому» — вероятно,
коллекцию заводили руками в панели и правила остались пустыми. Скрипт
только что пытался их выставить; раз проверка всё равно не прошла, значит
правка не применилась.

Что сделать: панель → Collections → нужная коллекция → вкладка API Rules →
в каждом из пяти полей написать   owner = @request.auth.id   → Save.
Для users: listRule и viewRule —   id = @request.auth.id   , createRule и
deleteRule — замок (только администратор).

Синхронизацию до этого не включайте.

BAD
  exit 1
fi
ok "Снаружи без входа не пускают"

IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

cat <<TEXT

================ ГОТОВО ================

В приложении: Настройки → Данные → Синхронизация

    адрес:  $IP:8090
    логин:  ${APP_USER:-<та почта, что завели в users>}
    пароль: тот, что задали

Дальше — «Войти», потом «Синхронизировать сейчас».

Если что-то не сойдётся, пришлите вывод этой команды целиком: в нём виден
ответ сервера, а по нему понятно, что именно не так.

TEXT
