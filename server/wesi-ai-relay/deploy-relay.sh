#!/usr/bin/env bash
#
# Install/update Wesi AI Relay on a foreign Linux server.
#
# The provider key lives only on this host. Main Wesi Server knows only the
# Relay HTTPS URL and the shared HMAC secret.
#
# Direct install (interactive/admin use):
#   WESI_MAIN_SHARED_SECRET=... GEMINI_API_KEY=... bash deploy-relay.sh --install
#
# CI-safe install:
#   bash deploy-relay.sh --install-from-b64 /tmp/wesi-relay-secrets.b64
#
# The b64 file contains only KEY_B64=value lines and is deleted immediately
# after decoding. This avoids putting secrets into the remote process command
# line, where other users could inspect them.

set -euo pipefail

APP_DIR="${WESI_RELAY_DIR:-/opt/wesi-ai-relay}"
ENV_FILE="/etc/wesi-ai-relay.env"
SERVICE="/etc/systemd/system/wesi-ai-relay.service"
RELAY_HOST="${WESI_RELAY_HOST:-127.0.0.1}"
RELAY_PORT="${WESI_RELAY_PORT:-8787}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "$*" >&2
  exit 2
}

contains_newline() {
  case "$1" in
    *$'\n'*|*$'\r'*) return 0 ;;
    *) return 1 ;;
  esac
}

decode_b64() {
  printf '%s' "$1" | base64 -d
}

load_b64_file() {
  local file="$1"
  [ -f "$file" ] || fail "Файл секретов не найден: $file"
  chmod 600 "$file" 2>/dev/null || true
  local key value decoded
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
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
  contains_newline "$WESI_MAIN_SHARED_SECRET" && fail "Shared secret содержит перевод строки"
  contains_newline "$GEMINI_API_KEY" && fail "Gemini key содержит перевод строки"
  contains_newline "${WESI_ZANE_TTS_VOICE:-Charon}" && fail "Имя голоса Зейна некорректно"
  contains_newline "${WESI_NIRVANA_TTS_VOICE:-Sulafat}" && fail "Имя голоса Нирваны некорректно"
}

install_relay() {
  require_secrets

  command -v node >/dev/null 2>&1 || fail "Node.js не установлен. Нужен Node 20 или новее."
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$major" -ge 20 ] || fail "Node $major слишком старый, нужен 20 или новее."

  mkdir -p "$APP_DIR"
  install -m 0644 "$SOURCE_DIR/server.mjs" "$APP_DIR/server.mjs"
  install -m 0644 "$SOURCE_DIR/auth.mjs" "$APP_DIR/auth.mjs"
  install -m 0644 "$SOURCE_DIR/google.mjs" "$APP_DIR/google.mjs"
  install -m 0644 "$SOURCE_DIR/google-media.mjs" "$APP_DIR/google-media.mjs"
  install -m 0644 "$SOURCE_DIR/google-artifact.mjs" "$APP_DIR/google-artifact.mjs"
  install -m 0644 "$SOURCE_DIR/media-cache.mjs" "$APP_DIR/media-cache.mjs"
  install -m 0644 "$SOURCE_DIR/package.json" "$APP_DIR/package.json"

  umask 077
  cat >"$ENV_FILE" <<ENV
WESI_MAIN_SHARED_SECRET=$WESI_MAIN_SHARED_SECRET
GEMINI_API_KEY=$GEMINI_API_KEY
WESI_RELAY_HOST=$RELAY_HOST
WESI_RELAY_PORT=$RELAY_PORT
WESI_ZANE_TTS_VOICE=${WESI_ZANE_TTS_VOICE:-Charon}
WESI_NIRVANA_TTS_VOICE=${WESI_NIRVANA_TTS_VOICE:-Sulafat}
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

  # MemoryDenyWriteExecute is intentionally NOT enabled. systemd documents it
  # as incompatible with JIT engines; Node/V8 generates executable code at
  # runtime. The remaining filesystem/device/kernel/network sandbox remains.
  systemctl daemon-reload
  systemctl enable --now wesi-ai-relay.service
  sleep 1

  local health
  health="$(curl -fsS --max-time 10 "http://$RELAY_HOST:$RELAY_PORT/health" || true)"
  printf '%s' "$health" | grep -q '"ok":true' || {
    echo "Relay не отвечает корректно на /health. Логи: journalctl -u wesi-ai-relay -n 80" >&2
    exit 4
  }
  printf '%s' "$health" | grep -q '"ready":true' || {
    echo "Relay запущен, но provider/shared-secret configuration не готова." >&2
    exit 4
  }

  cat <<TEXT
Relay запущен на $RELAY_HOST:$RELAY_PORT и готов принимать подписанные запросы.

Рекомендуемые production routes на Main Server:
  fast    = google/gemini-3.5-flash-lite
  pro     = google/gemini-3.6-flash
  maximum = google/gemini-3.6-flash

Natural TTS использует gemini-3.1-flash-tts-preview; голоса можно менять
через WESI_ZANE_TTS_VOICE / WESI_NIRVANA_TTS_VOICE без релиза приложения.
Image, Veo video и Lyria 3 music используют тот же GEMINI_API_KEY; тяжёлые
результаты передаются Main Server только через одноразовые Relay artifacts.
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
  --install)
    install_relay
    ;;
  --install-from-b64)
    [ $# -eq 2 ] || fail "Использование: $0 --install-from-b64 FILE"
    load_b64_file "$2"
    install_relay
    ;;
  --uninstall)
    uninstall_relay
    ;;
  *)
    echo "Использование: $0 [--install|--install-from-b64 FILE|--uninstall]" >&2
    exit 1
    ;;
esac
