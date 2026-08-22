#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR=/opt/wesi-aero-node-agent
SERVICE=wesi-aero-node-agent-ireland-bs
ROUTE_URL="${WESI_AERO_ROUTE_SERVER_URL:-http://127.0.0.1:8793}"
TOKEN="${WESI_AERO_ROUTE_SERVER_TOKEN:-}"

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo -n); fi
"${SUDO[@]}" mkdir -p "$INSTALL_DIR/src"
"${SUDO[@]}" install -m 0644 package.json "$INSTALL_DIR/package.json"
"${SUDO[@]}" install -m 0644 src/index.mjs "$INSTALL_DIR/src/index.mjs"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
[Unit]
Description=Wesi Aero Node Agent - Ireland BS
After=network-online.target wesi-aero-ireland-bs.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment=WESI_AERO_NODE_ID=ireland-bs
Environment=WESI_AERO_ROUTE_SERVER_URL=$ROUTE_URL
Environment=WESI_AERO_NODE_SERVICES=wesi-aero-ireland-bs
EOF
if [ -n "$TOKEN" ]; then
  printf 'Environment=WESI_AERO_ROUTE_SERVER_TOKEN=%s\n' "$TOKEN" >> "$TMP"
fi
cat >> "$TMP" <<EOF
ExecStart=/usr/bin/node $INSTALL_DIR/src/index.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" install -m 0644 "$TMP" "/etc/systemd/system/$SERVICE.service"
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now "$SERVICE"
"${SUDO[@]}" systemctl restart "$SERVICE"
"${SUDO[@]}" systemctl is-active --quiet "$SERVICE"
echo "Node Agent installed for ireland-bs -> $ROUTE_URL"
