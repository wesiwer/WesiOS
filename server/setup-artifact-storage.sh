#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-wesios-deploy}"
ROOT="${ARTIFACT_ROOT:-/srv/wesi-artifacts}"
SCRIPT_URL="https://raw.githubusercontent.com/wesiwer/WesiOS/chatgpt/gpt-5.6-work/server/promote-release.sh"

[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

id "$DEPLOY_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$DEPLOY_USER"
install -d -m 0750 -o root -g "$DEPLOY_USER" "$ROOT"

curl -fsSL "$SCRIPT_URL" -o /usr/local/sbin/wesi-promote-release
chmod 0755 /usr/local/sbin/wesi-promote-release

cat > /etc/sudoers.d/wesi-artifact-deploy <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/local/sbin/wesi-promote-release
EOF
chmod 0440 /etc/sudoers.d/wesi-artifact-deploy
visudo -cf /etc/sudoers.d/wesi-artifact-deploy

# Standard hierarchy for multiple future products.
for product in wesios; do
  for channel in app forecast-model; do
    install -d -m 0750 -o root -g "$DEPLOY_USER" "$ROOT/$product/$channel/releases"
  done
done

cat > /etc/logrotate.d/wesi-artifacts <<'EOF'
/var/log/wesi-artifact-download.log {
  weekly
  rotate 8
  compress
  missingok
  notifempty
  create 0640 root adm
}
EOF

echo "Artifact storage ready: $ROOT"
echo "Deploy user: $DEPLOY_USER"
echo "Add its SSH public key to /home/$DEPLOY_USER/.ssh/authorized_keys"
echo "GitHub secrets required: WESI_SERVER_HOST, WESI_SERVER_USER, WESI_SERVER_SSH_KEY"
