#!/usr/bin/env bash
# One-command remote deployment for WesiOS sync infrastructure.
# Secrets are accepted only through environment variables and are never
# written to the repository.

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-185.221.199.19}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_USER="${SERVER_USER:-root}"
ADMIN_EMAIL="${ADMIN_EMAIL:?Set ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?Set ADMIN_PASSWORD}"
APP_EMAIL="${APP_EMAIL:?Set APP_EMAIL}"
APP_PASSWORD="${APP_PASSWORD:?Set APP_PASSWORD}"
REPO_BRANCH="${REPO_BRANCH:-chatgpt/gpt-5.6-work}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"

SSH_OPTS=(
  -p "$SERVER_PORT"
  -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
)

if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
  SSH_OPTS+=( -i "$SSH_PRIVATE_KEY" )
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh client is required" >&2
  exit 1
fi

SSH_CMD=(ssh "${SSH_OPTS[@]}" "$SERVER_USER@$SERVER_HOST")

if [[ -n "${SSHPASS:-}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "SSHPASS is set but sshpass is not installed" >&2
    exit 1
  fi
  SSH_CMD=(sshpass -e ssh "${SSH_OPTS[@]}" "$SERVER_USER@$SERVER_HOST")
fi

echo "==> Checking SSH access to $SERVER_HOST:$SERVER_PORT"
"${SSH_CMD[@]}" 'printf "connected: "; hostname; id -u'

echo "==> Deploying WesiOS sync server"
"${SSH_CMD[@]}" \
  "ADMIN_EMAIL=$(printf '%q' "$ADMIN_EMAIL") ADMIN_PASSWORD=$(printf '%q' "$ADMIN_PASSWORD") APP_EMAIL=$(printf '%q' "$APP_EMAIL") APP_PASSWORD=$(printf '%q' "$APP_PASSWORD") REPO_BRANCH=$(printf '%q' "$REPO_BRANCH") bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
BASE_URL="https://raw.githubusercontent.com/wesiwer/WesiOS/${REPO_BRANCH}/server"

install -d -m 0700 /root/wesios-deploy
cd /root/wesios-deploy

curl -fsSL "$BASE_URL/install-sync.sh" -o install-sync.sh
curl -fsSL "$BASE_URL/setup-collections.sh" -o setup-collections.sh
curl -fsSL "$BASE_URL/wesios-agent.sh" -o wesios-agent.sh
chmod 0700 install-sync.sh setup-collections.sh wesios-agent.sh

bash ./install-sync.sh
bash ./setup-collections.sh \
  --admin "$ADMIN_EMAIL" \
  --admin-pass "$ADMIN_PASSWORD" \
  --user "$APP_EMAIL" \
  --user-pass "$APP_PASSWORD"

bash ./wesios-agent.sh --install

apt-get update -qq
apt-get install -y -qq sqlite3 curl
cat >/etc/cron.daily/pocketbase-backup <<'BACKUP'
#!/bin/sh
set -eu
DIR=/opt/pocketbase/backups
DB=/opt/pocketbase/pb_data/data.db
mkdir -p "$DIR"
if [ -f "$DB" ]; then
  sqlite3 "$DB" ".backup '$DIR/data-$(date +%F).db'"
  find "$DIR" -name 'data-*.db' -mtime +14 -delete
fi
BACKUP
chmod 0750 /etc/cron.daily/pocketbase-backup

systemctl is-enabled pocketbase
systemctl is-active pocketbase
curl -fsS http://127.0.0.1:8090/api/health
bash ./wesios-agent.sh --print
ufw status verbose || true

echo
printf 'WESIOS_DEPLOY_OK host=%s\n' "$(hostname)"
REMOTE

echo "==> Deployment completed"
