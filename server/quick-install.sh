#!/usr/bin/env bash
#
# WesiOS: весь сервер одной командой.
#
#   curl -fsSL https://raw.githubusercontent.com/wesiwer/WesiOS/main/server/quick-install.sh -o /root/wesios.sh && bash /root/wesios.sh
#
# Ставит PocketBase, создаёт коллекцию с правилами, заводит учётную запись,
# ставит агента для показа нагрузки — и печатает готовые строки, которые
# останется ввести в приложении.
#
# Пароли придумывает сам и записывает в /root/wesios-credentials.txt.
# Придумывать их человеку незачем: пароль, набранный руками в спешке, обычно
# слабее случайного и всё равно теряется.
#
# Повторный запуск ничего не ломает: существующее не пересоздаётся.

set -euo pipefail

BASE="${BASE:-https://raw.githubusercontent.com/wesiwer/WesiOS/main/server}"
CREDS="/root/wesios-credentials.txt"
ADMIN_MAIL="${ADMIN_MAIL:-admin@wesios.local}"
USER_MAIL="${USER_MAIL:-wesi@wesios.local}"
WITH_AGENT="${WITH_AGENT:-yes}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[0;31m!! %s\033[0m\n' "$1" >&2; }

if [[ "$(id -u)" != "0" ]]; then
  fail "Нужны права root. Зайдите как root или добавьте sudo."
  exit 1
fi

# Пароль из символов, которые нельзя перепутать при чтении с экрана: без
# похожих l/I/1 и O/0. Человеку эти пароли придётся один раз прочитать
# глазами и перенести в приложение.
genpass() {
  tr -dc 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789' \
    < /dev/urandom | head -c 20
}

# Если скрипт уже запускали, пароли берём прежние — иначе второй запуск
# оставил бы человека с паролями, которых нет в базе.
if [[ -f "$CREDS" ]]; then
  say "Нашёл прежнюю установку — беру пароли из $CREDS"
  # shellcheck disable=SC1090
  source <(grep -E '^(ADMIN_PASS|USER_PASS|ADMIN_MAIL|USER_MAIL)=' "$CREDS")
  ok "Пароли прежние"
else
  ADMIN_PASS="$(genpass)"
  USER_PASS="$(genpass)"
fi

# --------------------------------------------------------------- PocketBase

say "Ставлю PocketBase"
curl -fsSL "$BASE/install-sync.sh" -o /root/install-sync.sh
bash /root/install-sync.sh

say "Жду, пока служба поднимется"
for i in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:8090/api/health >/dev/null 2>&1; then
    ok "Отвечает"
    break
  fi
  sleep 2
  [[ $i -eq 30 ]] && { fail "PocketBase не поднялся за минуту. Смотрите: journalctl -u pocketbase -n 50"; exit 1; }
done

# --------------------------------------------------------- схема и учётка

say "Создаю коллекцию, правила и учётную запись"
curl -fsSL "$BASE/setup-collections.sh" -o /root/setup-collections.sh
bash /root/setup-collections.sh \
  --admin "$ADMIN_MAIL" --admin-pass "$ADMIN_PASS" \
  --user  "$USER_MAIL"  --user-pass  "$USER_PASS"

# ------------------------------------------------------------------- агент

if [[ "$WITH_AGENT" == "yes" ]]; then
  say "Ставлю агента (нагрузка сервера в приложении)"
  curl -fsSL "$BASE/wesios-agent.sh" -o /root/wesios-agent.sh
  bash /root/wesios-agent.sh --install >/dev/null
  ok "Готово"
fi

# ------------------------------------------------------------------- итог

IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
PB_VERSION="$(/opt/pocketbase/pocketbase --version 2>/dev/null | head -1 || echo 'неизвестна')"

cat > "$CREDS" <<CREDS_FILE
# WesiOS — доступы к серверу. Создано $(date '+%Y-%m-%d %H:%M').
# Восстановить пароли иначе нельзя: почтовые порты у хостера закрыты.

SERVER_IP=$IP
POCKETBASE_VERSION=$PB_VERSION

# Панель управления: http://$IP:8090/_/
ADMIN_MAIL=$ADMIN_MAIL
ADMIN_PASS=$ADMIN_PASS

# Это вводится в приложении: Настройки -> Данные -> Синхронизация
USER_MAIL=$USER_MAIL
USER_PASS=$USER_PASS
CREDS_FILE
chmod 600 "$CREDS"

cat <<TEXT

╔══════════════════════════════════════════════════════════════╗
║                        ВСЁ ГОТОВО                            ║
╚══════════════════════════════════════════════════════════════╝

В приложении: Настройки → Данные → Синхронизация

    адрес   $IP:8090
    логин   $USER_MAIL
    пароль  $USER_PASS

Системный администратор → добавить узел:

    адрес         $IP
    порт          8090
    адрес агента  http://$IP:8090/wesios-status.json

──────────────────────────────────────────────────────────────
Панель сервера: http://$IP:8090/_/
    логин   $ADMIN_MAIL
    пароль  $ADMIN_PASS

Версия PocketBase: $PB_VERSION

ЭТИ ПАРОЛИ БОЛЬШЕ НИГДЕ НЕ ПОЯВЯТСЯ.
Они записаны в $CREDS — перепишите их себе.
Почтовые порты у хостера закрыты, сбросить пароль письмом нельзя.
──────────────────────────────────────────────────────────────

TEXT
