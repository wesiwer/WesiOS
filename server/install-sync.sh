#!/usr/bin/env bash
#
# Установка сервера синхронизации WesiOS на чистую Ubuntu 24.04.
#
# Что делает: ставит PocketBase как системную службу, закрывает всё лишнее
# файрволом, включает автозапуск. Ничего не удаляет и ничего не перезаписывает
# без спроса — повторный запуск обновляет только сам PocketBase.
#
# Запускать от root:
#   bash install-sync.sh
#
# Дальше — server/README.md, раздел «Коллекция и правила».

set -euo pipefail

# Версия. По умолчанию — последняя выпущенная, её скрипт спрашивает у GitHub.
# Чтобы поставить конкретную (например, откатиться), задайте явно:
#   PB_VERSION=0.22.21 bash install-sync.sh
PB_VERSION="${PB_VERSION:-}"
PB_PORT="${PB_PORT:-8090}"
PB_DIR="/opt/pocketbase"
PB_USER="pocketbase"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

if [[ "$(id -u)" != "0" ]]; then
  echo "Нужны права root: sudo bash install-sync.sh" >&2
  exit 1
fi

say "Обновляю списки пакетов"
apt-get update -qq
apt-get install -y -qq unzip curl ca-certificates

say "Завожу отдельного пользователя $PB_USER"
# Служба не должна ходить под root: если её однажды взломают, взломщик
# получит один каталог, а не сервер целиком.
if ! id "$PB_USER" >/dev/null 2>&1; then
  useradd --system --home "$PB_DIR" --shell /usr/sbin/nologin "$PB_USER"
fi
mkdir -p "$PB_DIR"

if [[ -z "$PB_VERSION" ]]; then
  say "Узнаю последнюю версию PocketBase"
  # Тег вида v0.22.21 — ведущую «v» снимаем, в имени файла её нет.
  PB_VERSION="$(curl -fsSL https://api.github.com/repos/pocketbase/pocketbase/releases/latest \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"v?([^"]+)".*/\1/')"
  if [[ -z "$PB_VERSION" ]]; then
    echo "Не удалось узнать версию. Задайте вручную:" >&2
    echo "  PB_VERSION=0.22.21 bash install-sync.sh" >&2
    exit 1
  fi
fi

say "Скачиваю PocketBase $PB_VERSION"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  PB_ARCH="amd64" ;;
  aarch64) PB_ARCH="arm64" ;;
  *) echo "Неизвестная архитектура: $ARCH" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/pb.zip" \
  "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${PB_ARCH}.zip"
unzip -oq "$TMP/pb.zip" -d "$TMP"

systemctl stop pocketbase 2>/dev/null || true
install -m 0755 "$TMP/pocketbase" "$PB_DIR/pocketbase"
chown -R "$PB_USER:$PB_USER" "$PB_DIR"

say "Создаю службу systemd"
cat >/etc/systemd/system/pocketbase.service <<UNIT
[Unit]
Description=WesiOS sync (PocketBase)
After=network.target

[Service]
Type=simple
User=$PB_USER
Group=$PB_USER
WorkingDirectory=$PB_DIR
ExecStart=$PB_DIR/pocketbase serve --http=0.0.0.0:$PB_PORT --dir=$PB_DIR/pb_data
Restart=always
RestartSec=5

# Служба пишет только в свой каталог. Один процессор и два гигабайта —
# не то место, где стоит разрешать лишнее.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$PB_DIR

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now pocketbase

say "Настраиваю файрвол"
# Порядок важен: сначала разрешаем SSH, потом включаем ufw. Наоборот —
# верный способ отрезать себя от собственного сервера.
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH >/dev/null
  ufw allow "$PB_PORT/tcp" >/dev/null
  ufw allow 80/tcp >/dev/null     # понадобится Let's Encrypt
  ufw allow 443/tcp >/dev/null
  yes | ufw enable >/dev/null
  ufw status numbered
else
  echo "ufw не установлен — пропускаю. Проверьте файрвол вручную."
fi

say "Готово"
IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
cat <<TEXT

Панель управления:  http://$IP:$PB_PORT/_/
Адрес для WesiOS:   $IP:$PB_PORT

Дальше — два шага, оба в панели, оба обязательные:
  1. завести администратора (первый вход попросит сам);
  2. создать коллекцию и правила — см. server/README.md.

Служба:
  systemctl status pocketbase
  journalctl -u pocketbase -f

TEXT
