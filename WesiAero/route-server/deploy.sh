#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR=/opt/wesi-aero-route-server
CONFIG_DIR=/etc/wesi-aero/route-server
STATE_DIR=/var/lib/wesi-aero-route-server
SERVICE=wesi-aero-route-server
TOKEN="${WESI_AERO_ROUTE_SERVER_TOKEN:-}"

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo -n); fi
"${SUDO[@]}" mkdir -p "$INSTALL_DIR/src" "$INSTALL_DIR/test" "$CONFIG_DIR" "$STATE_DIR"
"${SUDO[@]}" install -m 0644 package.json "$INSTALL_DIR/package.json"
"${SUDO[@]}" install -m 0644 src/index.mjs "$INSTALL_DIR/src/index.mjs"
"${SUDO[@]}" install -m 0644 src/route-core.mjs "$INSTALL_DIR/src/route-core.mjs"
"${SUDO[@]}" install -m 0644 src/auto-route.mjs "$INSTALL_DIR/src/auto-route.mjs"

if [ ! -f "$CONFIG_DIR/config.json" ] || [ "${WESI_AERO_ROUTE_REPLACE_CONFIG:-false}" = true ]; then
  "${SUDO[@]}" install -m 0640 config.example.json "$CONFIG_DIR/config.json"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
[Unit]
Description=Wesi Aero Route Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment=WESI_AERO_ROUTE_CONFIG=$CONFIG_DIR/config.json
Environment=WESI_AERO_ROUTE_STATE=$STATE_DIR/route-state.json
EOF
if [ -n "$TOKEN" ]; then
  printf 'Environment=WESI_AERO_ROUTE_TOKEN=%s\n' "$TOKEN" >> "$TMP"
fi
cat >> "$TMP" <<EOF
ExecStart=/usr/bin/node $INSTALL_DIR/src/index.mjs
Restart=always
RestartSec=2
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$STATE_DIR

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" install -m 0644 "$TMP" "/etc/systemd/system/$SERVICE.service"
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now "$SERVICE"
"${SUDO[@]}" systemctl restart "$SERVICE"
"${SUDO[@]}" systemctl is-active --quiet "$SERVICE"
curl -fsS http://127.0.0.1:8793/healthz >/dev/null
echo 'Wesi Aero Route Server installed on 127.0.0.1:8793'
