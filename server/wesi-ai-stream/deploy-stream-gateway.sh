#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
SECRETS_FILE="${2:-$SOURCE_DIR/stream-secrets.b64}"
INSTALL_DIR="/opt/wesi-ai-stream"
ENV_FILE="/etc/wesi-ai-stream.env"
SERVICE_FILE="/etc/systemd/system/wesi-ai-stream.service"
SERVICE_USER="wesi-ai-stream"

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo -n); fi

RUNTIME_FILES=(
  server.mjs
  gateway.mjs
  persona_coagent.mjs
  persona_coagent_orchestrator.mjs
  dynamic_subagent.mjs
  dynamic_subagent_orchestrator.mjs
  public_deliberation.mjs
  multi_agent_workspace.mjs
  package.json
)

for required in "${RUNTIME_FILES[@]}"; do
  [ -f "$SOURCE_DIR/$required" ] || { echo "Missing stream runtime file: $required" >&2; exit 2; }
done
[ -f "$SECRETS_FILE" ]
command -v node >/dev/null 2>&1

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  "${SUDO[@]}" useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

"${SUDO[@]}" install -d -o root -g "$SERVICE_USER" -m 0750 "$INSTALL_DIR"
for file in "${RUNTIME_FILES[@]}"; do
  "${SUDO[@]}" install -o root -g "$SERVICE_USER" -m 0640 "$SOURCE_DIR/$file" "$INSTALL_DIR/$file"
done

TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT
umask 077
: > "$TMP_ENV"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  key="${line%%=*}"
  value="${line#*=}"
  [ "$key" != "$line" ] || { echo "Invalid secret line" >&2; exit 2; }
  case "$key" in
    WESI_STREAM_SECRET_B64|WESI_MAIN_SHARED_SECRET_B64|WESI_RELAY_URL_B64|WESI_POCKETBASE_URL_B64) ;;
    *) echo "Unexpected stream secret key: $key" >&2; exit 2 ;;
  esac
  decoded="$(printf '%s' "$value" | base64 -d)"
  case "$key" in
    WESI_STREAM_SECRET_B64) out_key=WESI_STREAM_SECRET ;;
    WESI_MAIN_SHARED_SECRET_B64) out_key=WESI_MAIN_SHARED_SECRET ;;
    WESI_RELAY_URL_B64) out_key=WESI_RELAY_URL ;;
    WESI_POCKETBASE_URL_B64) out_key=WESI_POCKETBASE_URL ;;
  esac
  printf '%s=%s\n' "$out_key" "$decoded" >> "$TMP_ENV"
done < "$SECRETS_FILE"

grep -q '^WESI_STREAM_SECRET=.' "$TMP_ENV"
grep -q '^WESI_MAIN_SHARED_SECRET=.' "$TMP_ENV"
grep -Eq '^WESI_RELAY_URL=https://' "$TMP_ENV"
grep -Eq '^WESI_POCKETBASE_URL=https?://' "$TMP_ENV"

"${SUDO[@]}" install -o root -g "$SERVICE_USER" -m 0640 "$TMP_ENV" "$ENV_FILE"

TMP_SERVICE="$(mktemp)"
cat > "$TMP_SERVICE" <<'EOF'
[Unit]
Description=Wesi AI Streaming Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wesi-ai-stream
Group=wesi-ai-stream
WorkingDirectory=/opt/wesi-ai-stream
EnvironmentFile=/etc/wesi-ai-stream.env
Environment=WESI_STREAM_HOST=127.0.0.1
Environment=WESI_STREAM_PORT=8792
ExecStart=/usr/bin/env node /opt/wesi-ai-stream/server.mjs
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/tmp

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" install -o root -g root -m 0644 "$TMP_SERVICE" "$SERVICE_FILE"
rm -f "$TMP_SERVICE"

"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now wesi-ai-stream
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:8792/health >/dev/null; then
    exit 0
  fi
  sleep 1
done
"${SUDO[@]}" systemctl status wesi-ai-stream --no-pager -l || true
exit 1
