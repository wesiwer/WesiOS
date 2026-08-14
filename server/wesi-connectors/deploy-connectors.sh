#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${WESI_CONNECTOR_DIR:-/opt/wesi-connectors}"
ENV_FILE="/etc/wesi-connectors.env"
SERVICE="/etc/systemd/system/wesi-connectors.service"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "$*" >&2; exit 2; }

[ "$(id -u)" -eq 0 ] || fail "Запустите deploy-connectors.sh от root"
command -v node >/dev/null 2>&1 || fail "Node.js 20+ не установлен"
[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 20 ] || fail "Нужен Node.js 20+"

: "${WESI_CONNECTOR_MASTER_KEY:?WESI_CONNECTOR_MASTER_KEY is required}"
: "${WESI_CONNECTOR_SHARED_SECRET:?WESI_CONNECTOR_SHARED_SECRET is required}"
: "${WESI_CONNECTOR_PUBLIC_BASE:?WESI_CONNECTOR_PUBLIC_BASE is required}"
: "${WESI_GITHUB_CLIENT_ID:?WESI_GITHUB_CLIENT_ID is required}"
: "${WESI_GITHUB_CLIENT_SECRET:?WESI_GITHUB_CLIENT_SECRET is required}"

[ "${#WESI_CONNECTOR_MASTER_KEY}" -ge 32 ] || fail "Connector master key is too short"
[ "${#WESI_CONNECTOR_SHARED_SECRET}" -ge 32 ] || fail "Connector shared secret is too short"

mkdir -p "$APP_DIR" /var/lib/wesi-connectors
for file in server.mjs policy.mjs vault.mjs github.mjs package.json; do
  install -m 0644 "$SOURCE_DIR/$file" "$APP_DIR/$file"
done
chmod 700 /var/lib/wesi-connectors

umask 077
cat >"$ENV_FILE" <<ENV
WESI_CONNECTOR_HOST=127.0.0.1
WESI_CONNECTOR_PORT=8791
WESI_CONNECTOR_VAULT_DIR=/var/lib/wesi-connectors
WESI_CONNECTOR_MASTER_KEY=$WESI_CONNECTOR_MASTER_KEY
WESI_CONNECTOR_SHARED_SECRET=$WESI_CONNECTOR_SHARED_SECRET
WESI_CONNECTOR_PUBLIC_BASE=$WESI_CONNECTOR_PUBLIC_BASE
WESI_GITHUB_CLIENT_ID=$WESI_GITHUB_CLIENT_ID
WESI_GITHUB_CLIENT_SECRET=$WESI_GITHUB_CLIENT_SECRET
ENV
chmod 600 "$ENV_FILE"

id -u wesi-connectors >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin wesi-connectors
chown -R root:root "$APP_DIR"
chown -R wesi-connectors:wesi-connectors /var/lib/wesi-connectors

cat >"$SERVICE" <<UNIT
[Unit]
Description=Wesi Connectors Broker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wesi-connectors
Group=wesi-connectors
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$(command -v node) $APP_DIR/server.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/wesi-connectors
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
systemctl enable --now wesi-connectors.service
systemctl restart wesi-connectors.service
sleep 2
curl -fsS http://127.0.0.1:8791/health | grep -q '"ok":true' || {
  systemctl status wesi-connectors --no-pager -l || true
  journalctl -u wesi-connectors -n 100 --no-pager || true
  fail "Wesi Connectors health-check failed"
}

echo "Wesi Connectors запущен на 127.0.0.1:8791"
