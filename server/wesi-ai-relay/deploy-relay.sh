#!/usr/bin/env bash
# Install/update Wesi AI Relay on a Debian/Ubuntu Linux server.
set -euo pipefail

APP_DIR="${WESI_RELAY_DIR:-/opt/wesi-ai-relay}"
ENV_FILE="/etc/wesi-ai-relay.env"
PROVIDER_ENV_FILE="/etc/wesi-ai-providers.env"
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
      GEMINI_API_KEY_2_B64) GEMINI_API_KEY_2="$decoded" ;;
      GEMINI_API_KEY_3_B64) GEMINI_API_KEY_3="$decoded" ;;
      GEMINI_API_KEY_4_B64) GEMINI_API_KEY_4="$decoded" ;;
      GEMINI_API_KEY_5_B64) GEMINI_API_KEY_5="$decoded" ;;
      WESI_ZANE_TTS_VOICE_B64) WESI_ZANE_TTS_VOICE="$decoded" ;;
      WESI_NIRVANA_TTS_VOICE_B64) WESI_NIRVANA_TTS_VOICE="$decoded" ;;
      GROQ_API_KEY_B64) GROQ_API_KEY="$decoded" ;;
      MISTRAL_API_KEY_B64) MISTRAL_API_KEY="$decoded" ;;
      OPENROUTER_API_KEY_B64) OPENROUTER_API_KEY="$decoded" ;;
      *) fail "Неизвестное поле в файле секретов: $key" ;;
    esac
  done < "$file"
  rm -f "$file"
  export WESI_MAIN_SHARED_SECRET GEMINI_API_KEY
  export GEMINI_API_KEY_2="${GEMINI_API_KEY_2:-}" GEMINI_API_KEY_3="${GEMINI_API_KEY_3:-}"
  export GEMINI_API_KEY_4="${GEMINI_API_KEY_4:-}" GEMINI_API_KEY_5="${GEMINI_API_KEY_5:-}"
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
  local optional
  for optional in GEMINI_API_KEY_2 GEMINI_API_KEY_3 GEMINI_API_KEY_4 GEMINI_API_KEY_5 GROQ_API_KEY MISTRAL_API_KEY OPENROUTER_API_KEY; do
    if [ -n "${!optional:-}" ] && contains_newline "${!optional}"; then fail "$optional содержит перевод строки"; fi
  done
  return 0
}

install_node24() {
  local current=0
  if command -v node >/dev/null 2>&1; then
    current="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
  fi
  if [ "${current:-0}" -ge 20 ]; then
    echo "Node.js $(node --version) уже установлен."
    return 0
  fi

  command -v apt-get >/dev/null 2>&1 || fail "Node.js 20+ не найден, а автоустановка поддерживает Debian/Ubuntu."
  echo "Устанавливаю официальный Node.js 24 LTS с проверкой SHA-256..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl xz-utils

  local machine arch filename version tmp expected actual root
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) fail "Неподдерживаемая архитектура для Node.js: $machine" ;;
  esac

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL --retry 3 --retry-delay 2 \
    https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt -o "$tmp/SHASUMS256.txt"
  filename="$(awk -v a="$arch" '$2 ~ ("^node-v[0-9.]+-linux-" a "\\.tar\\.xz$") {print $2; exit}' "$tmp/SHASUMS256.txt")"
  [ -n "$filename" ] || fail "Не удалось определить официальный архив Node.js 24 для $arch"
  version="$(printf '%s' "$filename" | sed -E 's/^node-(v[0-9.]+)-linux-[^.]+\.tar\.xz$/\1/')"
  [ -n "$version" ] || fail "Не удалось определить версию Node.js"
  curl -fsSL --retry 3 --retry-delay 2 \
    "https://nodejs.org/dist/latest-v24.x/$filename" -o "$tmp/$filename"
  expected="$(awk -v f="$filename" '$2 == f {print $1}' "$tmp/SHASUMS256.txt")"
  actual="$(sha256sum "$tmp/$filename" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || fail "SHA-256 Node.js не совпал"

  root="/usr/local/lib/nodejs/$version"
  rm -rf "$root"
  mkdir -p "$root"
  tar -xJf "$tmp/$filename" --strip-components=1 -C "$root"
  ln -sfn "$root/bin/node" /usr/local/bin/node
  ln -sfn "$root/bin/npm" /usr/local/bin/npm
  ln -sfn "$root/bin/npx" /usr/local/bin/npx
  if [ -e "$root/bin/corepack" ]; then ln -sfn "$root/bin/corepack" /usr/local/bin/corepack; fi
  hash -r
  node --version
  [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 20 ] || fail "Node.js установился некорректно"
  trap - RETURN
  rm -rf "$tmp"
}

install_attachment_tools() {
  if command -v 7z >/dev/null 2>&1; then return 0; fi
  command -v apt-get >/dev/null 2>&1 || fail "7z не найден, а автоустановка archive tools поддерживает Debian/Ubuntu."
  echo "Устанавливаю безопасный extractor для Wesi AI attachments..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y p7zip-full file
  command -v 7z >/dev/null 2>&1 || fail "Не удалось установить 7z"
}

install_relay() {
  require_secrets
  install_node24
  install_attachment_tools
  local node_bin
  node_bin="$(command -v node)"
  [ -x "$node_bin" ] || fail "Node.js executable не найден после установки"

  mkdir -p "$APP_DIR"
  for file in server.mjs auth.mjs google.mjs text-stream.mjs attachment-preprocessor.mjs staged-upload.mjs google-media.mjs google-artifact.mjs media-cache.mjs package.json; do
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

  : >"$PROVIDER_ENV_FILE"
  [ -n "${GEMINI_API_KEY_2:-}" ] && printf "GEMINI_API_KEY_2=%s\n" "$GEMINI_API_KEY_2" >>"$PROVIDER_ENV_FILE"
  [ -n "${GEMINI_API_KEY_3:-}" ] && printf "GEMINI_API_KEY_3=%s\n" "$GEMINI_API_KEY_3" >>"$PROVIDER_ENV_FILE"
  [ -n "${GEMINI_API_KEY_4:-}" ] && printf "GEMINI_API_KEY_4=%s\n" "$GEMINI_API_KEY_4" >>"$PROVIDER_ENV_FILE"
  [ -n "${GEMINI_API_KEY_5:-}" ] && printf "GEMINI_API_KEY_5=%s\n" "$GEMINI_API_KEY_5" >>"$PROVIDER_ENV_FILE"
  [ -n "${GROQ_API_KEY:-}" ] && printf "GROQ_API_KEY=%s\n" "$GROQ_API_KEY" >>"$PROVIDER_ENV_FILE"
  [ -n "${MISTRAL_API_KEY:-}" ] && printf "MISTRAL_API_KEY=%s\n" "$MISTRAL_API_KEY" >>"$PROVIDER_ENV_FILE"
  [ -n "${OPENROUTER_API_KEY:-}" ] && printf "OPENROUTER_API_KEY=%s\n" "$OPENROUTER_API_KEY" >>"$PROVIDER_ENV_FILE"

  id -u wesi-relay >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin wesi-relay
  chown -R root:root "$APP_DIR"
  chown root:wesi-relay "$ENV_FILE" "$PROVIDER_ENV_FILE"
  chmod 640 "$ENV_FILE" "$PROVIDER_ENV_FILE"

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
EnvironmentFile=-$PROVIDER_ENV_FILE
ExecStart=$node_bin $APP_DIR/server.mjs
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
  systemctl enable wesi-ai-relay.service
  systemctl restart wesi-ai-relay.service
  sleep 2
  local health
  health="$(curl -fsS --max-time 10 "http://$RELAY_HOST:$RELAY_PORT/health" || true)"
  if ! printf '%s' "$health" | grep -q '"ok":true'; then
    systemctl status wesi-ai-relay --no-pager -l || true
    journalctl -u wesi-ai-relay -n 100 --no-pager || true
    fail "Relay не отвечает корректно на /health"
  fi
  printf '%s' "$health" | grep -q '"ready":true' || fail "Relay запущен, но provider/shared-secret configuration не готова"
  printf '%s' "$health" | grep -q '"attachments"' || fail "Relay запущен со старой версией без Universal Attachments"

  cat <<TEXT
Relay запущен на $RELAY_HOST:$RELAY_PORT.
Text routing управляется Main Server (Fast / Pro / Ultra).
Universal attachments: image/audio/video/PDF/text/Markdown/documents/archives enabled.
Natural TTS использует Gemini и остаётся серверной функцией.
Image/video/music по умолчанию НЕ используют платные cloud endpoints:
WESI_ENABLE_PAID_MEDIA=false. Для бесплатной генерации WesiOS устанавливает
отдельные Wesi Media Engines из Wesi artifact storage.
TEXT
}

uninstall_relay() {
  systemctl disable --now wesi-ai-relay.service 2>/dev/null || true
  rm -f "$SERVICE" "$ENV_FILE" "$PROVIDER_ENV_FILE"
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