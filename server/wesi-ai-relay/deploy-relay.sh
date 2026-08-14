#!/usr/bin/env bash
# Install/update Wesi AI Relay on a foreign Linux server.
# Provider keys live only on this host; Main Wesi Server receives no provider secrets.
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
  local key value decoded
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    decoded="$(decode_b64 "$value")" || fail "Не удалось декодировать $key"
    case "$key" in
      WESI_MAIN_SHARED_SECRET_B64) WESI_MAIN_SHARED_SECRET="$decoded" ;;
      GEMINI_API_KEY_B64) GEMINI_API_KEY="$decoded" ;;
      OPENAI_API_KEY_B64) OPENAI_API_KEY="$decoded" ;;
      ANTHROPIC_API_KEY_B64) ANTHROPIC_API_KEY="$decoded" ;;
      XAI_API_KEY_B64) XAI_API_KEY="$decoded" ;;
      WESI_ZANE_TTS_VOICE_B64) WESI_ZANE_TTS_VOICE="$decoded" ;;
      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE="$decoded" ;;
      *) fail "Неизвестное поле в файле секретов: $key" ;;
    esac
  done < "$file"
  rm -f "$file"
  export WESI_MAIN_SHARED_SECRET GEMINI_API_KEY
  export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
  export XAI_API_KEY="${XAI_API_KEY:-}"
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
  for pair in \
    "GEMINI_API_KEY:${GEMINI_API_KEY:-}" \
    "OPENAI_API_KEY:${OPENAI_API_KEY:-}" \
    "ANTHROPIC_API_KEY:${ANTHROPIC_API_KEY:-}" \
    "XAI_API_KEY:${XAI_API_KEY:-}"; do
    local name="${pair%%:*}" value="${pair#*:}"
    [ -z "$value" ] || ! contains_newline "$value" || fail "$name содержит перевод строки"
  done
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
  local installed=0
  for src in "$SOURCE_DIR"/*.mjs; do
    [ -f "$src" ] || continue
    install -m 0644 "$src" "$APP_DIR/$(basename "$src")"
    installed=$((installed+1))
  done
  [ "$installed" -ge 6 ] || fail "Неполный bundle Relay: найдено $installed .mjs файлов"
  install -m 0644 "$SOURCE_DIR/package.json" "$APP_DIR/package.json"

  umask 077
  cat >"$ENV_FILE" <<ENV
WESI_MAIN_SHARED_SECRET=$WESI_MAIN_SHARED_SECRET
GEMINI_API_KEY=${GEMINI_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
XAI_API_KEY=${XAI_API_KEY:-}
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

  echo "Relay установлен. Gemini обязателен для media/TTS; OpenAI, Anthropic и xAI подключаются автоматически при наличии соответствующих ключей."
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
