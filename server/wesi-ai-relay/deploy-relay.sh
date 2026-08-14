#!/usr/bin/env bash
# Install/update Wesi AI Relay on a foreign Linux server.
set -euo pipefail

APP_DIR="${WESI_RELAY_DIR:-/opt/wesi-ai-relay}"
ENV_FILE="/etc/wesi-ai-relay.env"
SERVICE="/etc/systemd/system/wesi-ai-relay.service"
RELAY_HOST="${WESI_RELAY_HOST:-127.0.0.1}"
RELAY_PORT="${WESI_RELAY_PORT:-8787}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "$*" >&2; exit 2; }
contains_newline() { case "$1" in *$'\n'*|*$'\r'*) return 0 ;; *) return 1 ;; esac; }
decode_b64() { printf '%s' "$1" | base64 -d; }

load_b64_file() {
  local file="$1"
  [ -f "$file" ] || fail "Файл секретов не найден: $file"
  chmod 600 "$file" 2>/dev/null || true
  local line key value decoded
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [ "$key" != "$line" ] || fail "Некорректная строка секретов"
    decoded="$(decode_b64 "$value")" || fail "Не удалось декодировать $key"
    case "$key" in
      WESI_MAIN_SHARED_SECRET_B64) WESI_MAIN_SHARED_SECRET="$decoded" ;;
      GEMINI_API_KEY_B64) GEMINI_API_KEY="$decoded" ;;
      WESI_ZANE_TTS_VOICE_B64) WESI_ZANE_TTS_VOICE="$decoded" ;;
      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE="$decoded" ;;
      *) fail "Неизвестное поле в файле секретов: $key" ;;
    esac
  done < "$file"
  rm -f "$file"
  export WESI_MAIN_SHARED_SECRET GEMINI_API_KEY
  export WESI_ZANE_TTS_VOICE="${WESI_ZANE_TTS_VOICE:-Charon}"
  export WESI_NIRVANA_TTS_VOICE="${WESI_NIRVANA_TTS_VOICE:-Sulafat}"
}

require_secrets() {
  local missing=()
  [ -n "${WESI_MAIN_SHARED_SECRET:-}" ] || missing+=("WESI_MAIN_SHARED_SECRET")
  [ -n "${GEMINI_API_KEY:-}" ] || missing+=("GEMINI_API_KEY")
  [ ${#missing[@]} -eq 0 ] || fail "Не заданы: ${missing[*]}"
  [ "${#WESI_MAIN_SHARED_SECRET}" -ge 32 ] || fail "WESI_MAIN_SHARED_SECRET короче 32 символов"
  if contains_newline "$WESI_MAIN_SHARED_SECRET"; then fail "Shared secret содержит перевод строки"; fi
  if contains_newline "$GEMINI_API_KEY"; then fail "Gemini key содержит перевод строки"; fi
  return 0
}

install_relay() {
  require_secrets
  command -v node >/dev/null 2>&1 || fail "Node.js не установлен. Нужен Node 20 или новее."
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$major" -ge 20 ] || fail "Node $major слишком старый, нужен 20 или новее."

  mkdir -p "$APP_DIR"
  for file in server.mjs auth.mjs google.mjs google-media.mjs google-artifact.mjs media-cache.mjs package.json; do
    install -m 0644 "$SOURCE_DIR/$file" "$APP_DIR/$file"
  done

  umask 077
  cat >"$ENV_FILE" <<ENV
WESI_MAIN_SHARED_SECRET=$WESI_MAIN_SHARED_SECRET
GEMINI_API_KEY=$GEMINI_API_KEY
WESI_RELAY_HOST=$RELAY_HOST
WESI_RELAY_PORT=$RELAY_PORT
WESI_ZANE_TTS_VOICE=${WESI_ZANE_TTS_VOICE:-Charon}
WESI_NIRVANA_TTS_VOICE=${WESI_NIRVANA_TTS_VOICE:-Sulafat}
WESI_ENABLE_PAID_MEDIA=${WESI_ENABLE_PAID_MEDIA:-false}
ENV

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
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=$APP_DIR
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now wesi-ai-relay.service
  sleep 1
  local health
  health="$(curl -fsS --max-time 10 "http://$RELAY_HOST:$RELAY_PORT/health" || true)"
  printf '%s' "$health" | grep -q '"ok":true' || fail "Relay не отвечает корректно на /health"
  printf '%s' "$health" | grep -q '"ready":true' || fail "Relay запущен, но provider/shared-secret configuration не готова"

  cat <<TEXT
Relay запущен на $RELAY_HOST:$RELAY_PORT.
Text routing управляется Main Server (Fast / Pro / Ultra).
Natural TTS использует Gemini и остаётся серверной функцией.
Image/video/music по умолчанию НЕ используют платные cloud endpoints:
WESI_ENABLE_PAID_MEDIA=false. Для бесплатной генерации WesiOS устанавливает
отдельные Wesi Media Engines из Wesi artifact storage.
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
  --install) install_relay ;;
  --install-from-b64)
    [ $# -eq 2 ] || fail "Использование: $0 --install-from-b64 FILE"
    load_b64_file "$2"
    install_relay
    ;;
  --uninstall) uninstall_relay ;;
  *) echo "Использование: $0 [--install|--install-from-b64 FILE|--uninstall]" >&2; exit 1 ;;
esac
