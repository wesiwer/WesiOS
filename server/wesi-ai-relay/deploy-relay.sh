#!/usr/bin/env bash
#
# Выкладка Wesi AI Relay на зарубежный сервер.
#
# ЗАЧЕМ ОТДЕЛЬНЫЙ СЕРВЕР. Провайдер модели недоступен из России, и ключ к
# нему не должен лежать ни в приложении, ни на основном сервере. Поэтому
# цепочка такая:
#
#   WesiOS → api.wesi-inc.ru → этот Relay → Gemini → обратно
#
# Ключ провайдера живёт только здесь. Основной сервер знает адрес Relay и
# общий секрет — и больше ничего.
#
# УСТАНОВКА (от root на зарубежном сервере):
#   WESI_MAIN_SHARED_SECRET=... GEMINI_API_KEY=... \
#     bash deploy-relay.sh --install
#
# Секреты передаются переменными окружения и попадают только в файл
# /etc/wesi-ai-relay.env с правами 600. В командной строке они видны в
# истории оболочки — очистите её или используйте `read -s`.
#
# СНЯТЬ:
#   bash deploy-relay.sh --uninstall

set -euo pipefail

APP_DIR="${WESI_RELAY_DIR:-/opt/wesi-ai-relay}"
ENV_FILE="/etc/wesi-ai-relay.env"
SERVICE="/etc/systemd/system/wesi-ai-relay.service"
RELAY_HOST="${WESI_RELAY_HOST:-127.0.0.1}"
RELAY_PORT="${WESI_RELAY_PORT:-8787}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_secrets() {
  local missing=()
  [ -n "${WESI_MAIN_SHARED_SECRET:-}" ] || missing+=("WESI_MAIN_SHARED_SECRET")
  [ -n "${GEMINI_API_KEY:-}" ] || missing+=("GEMINI_API_KEY")
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Не заданы: ${missing[*]}" >&2
    exit 2
  fi
  # Секрет короче 32 символов Relay отвергает сам — лучше сказать об этом
  # сейчас, чем получить молчаливый 503 после установки.
  if [ "${#WESI_MAIN_SHARED_SECRET}" -lt 32 ]; then
    echo "WESI_MAIN_SHARED_SECRET короче 32 символов — Relay такой не примет." >&2
    exit 2
  fi
}

install_relay() {
  require_secrets

  command -v node >/dev/null 2>&1 || {
    echo "Node.js не установлен. Нужен Node 20 или новее." >&2
    exit 3
  }
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -lt 20 ]; then
    echo "Node $major слишком старый, нужен 20 или новее." >&2
    exit 3
  fi

  mkdir -p "$APP_DIR"
  install -m 0644 "$SOURCE_DIR/server.mjs" "$APP_DIR/server.mjs"
  install -m 0644 "$SOURCE_DIR/auth.mjs" "$APP_DIR/auth.mjs"
  install -m 0644 "$SOURCE_DIR/google.mjs" "$APP_DIR/google.mjs"
  install -m 0644 "$SOURCE_DIR/package.json" "$APP_DIR/package.json"

  umask 077
  cat >"$ENV_FILE" <<ENV
WESI_MAIN_SHARED_SECRET=$WESI_MAIN_SHARED_SECRET
GEMINI_API_KEY=$GEMINI_API_KEY
WESI_RELAY_HOST=$RELAY_HOST
WESI_RELAY_PORT=$RELAY_PORT
ENV
  chmod 600 "$ENV_FILE"

  id -u wesi-relay >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin wesi-relay
  chown -R root:root "$APP_DIR"
  chown root:wesi-relay "$ENV_FILE"
  chmod 640 "$ENV_FILE"

  cat >"$SERVICE" <<UNIT
[Unit]
Description=Wesi AI Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wesi-relay
Group=wesi-relay
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/env node $APP_DIR/server.mjs
Restart=always
RestartSec=3

# Relay держит ключ провайдера, поэтому у него нет причин уметь что-то ещё.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=$APP_DIR
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now wesi-ai-relay.service
  sleep 1

  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "http://$RELAY_HOST:$RELAY_PORT/health" || echo 000)"
  if [ "$code" != "200" ]; then
    echo "Relay не отвечает на /health (код $code). Логи: journalctl -u wesi-ai-relay -n 50" >&2
    exit 4
  fi

  cat <<TEXT

Relay запущен на $RELAY_HOST:$RELAY_PORT и отвечает на /health.

ОСТАЛОСЬ ДВА ШАГА.

1. HTTPS. Relay намеренно слушает только localhost: наружу его выставляет
   nginx с сертификатом. Пример конфигурации — nginx-relay.conf рядом с
   этим скриптом.

2. Основной сервер. На api.wesi-inc.ru создайте
   /opt/pocketbase/pb_hooks/.wesi-ai-relay.json с правами 600:

   {
     "url": "https://<адрес-relay>",
     "sharedSecret": "<тот же WESI_MAIN_SHARED_SECRET>",
     "routes": {
       "fast": "google/gemini-2.5-flash",
       "pro": "google/gemini-2.5-pro",
       "maximum": "google/gemini-2.5-pro"
     }
   }

   Секрет обязан совпасть дословно: подпись считается по нему с обеих
   сторон, и расхождение выглядит как 401, а не как ошибка настройки.

TEXT
}

uninstall_relay() {
  systemctl disable --now wesi-ai-relay.service 2>/dev/null || true
  rm -f "$SERVICE" "$ENV_FILE"
  rm -rf "$APP_DIR"
  systemctl daemon-reload
  echo "Relay снят. Пользователь wesi-relay оставлен."
}

case "${1:---help}" in
  --install)   install_relay ;;
  --uninstall) uninstall_relay ;;
  *)
    echo "Использование: $0 [--install|--uninstall]" >&2
    exit 1
    ;;
esac
