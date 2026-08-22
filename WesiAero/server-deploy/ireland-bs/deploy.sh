#!/usr/bin/env bash
set -euo pipefail

PORT="${WESI_AERO_REALITY_PORT:-8443}"
SERVER_NAME="${WESI_AERO_REALITY_SERVER_NAME:-www.cloudflare.com}"
TARGET="${WESI_AERO_REALITY_TARGET:-${SERVER_NAME}:443}"
INSTALL_DIR=/opt/wesi-aero-xray
CONFIG_DIR=/etc/wesi-aero/ireland-bs
CONFIG_FILE="$CONFIG_DIR/xray.json"
ENV_FILE="$CONFIG_DIR/credentials.env"
CLIENT_FILE="$CONFIG_DIR/client-uri.txt"
SERVICE=wesi-aero-ireland-bs

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo -n); fi

case "$PORT" in ''|*[!0-9]*) echo 'invalid port' >&2; exit 2;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { echo 'invalid port' >&2; exit 2; }
[[ "$SERVER_NAME" =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'invalid REALITY server name' >&2; exit 2; }

# Do not collide with the live Wesi AI services on this VPS.
for reserved in 443 8787 8792; do
  [ "$PORT" -ne "$reserved" ] || { echo "port $PORT is reserved by Wesi AI" >&2; exit 3; }
done

if "${SUDO[@]}" ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)$PORT$"; then
  if ! "${SUDO[@]}" systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    echo "TCP/$PORT is already occupied by another service" >&2
    "${SUDO[@]}" ss -ltnp | grep -E ":$PORT\\b" || true
    exit 4
  fi
fi

# Validate that the camouflage target is actually reachable from the VPS.
TARGET_HOST="${TARGET%:*}"
TARGET_PORT="${TARGET##*:}"
timeout 8 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$SERVER_NAME" </dev/null 2>/dev/null | grep -q 'BEGIN CERTIFICATE' || {
  echo "REALITY target $TARGET with SNI $SERVER_NAME is not TLS-reachable" >&2
  exit 5
}

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) XRAY_ARCH=Xray-linux-64;;
  aarch64|arm64) XRAY_ARCH=Xray-linux-arm64-v8a;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 6;;
esac

"${SUDO[@]}" mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ ! -x "$INSTALL_DIR/xray" ]; then
  TAG="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$TAG" ] || { echo 'cannot resolve latest Xray release' >&2; exit 7; }
  curl -fL --retry 3 -o "$TMP/xray.zip" "https://github.com/XTLS/Xray-core/releases/download/$TAG/$XRAY_ARCH.zip"
  unzip -q "$TMP/xray.zip" xray -d "$TMP"
  "${SUDO[@]}" install -m 0755 "$TMP/xray" "$INSTALL_DIR/xray"
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

UUID="${UUID:-$($INSTALL_DIR/xray uuid)}"
SHORT_ID="${SHORT_ID:-$(openssl rand -hex 8)}"
if [ -z "${PRIVATE_KEY:-}" ] || [ -z "${PUBLIC_KEY:-}" ]; then
  KEYS="$($INSTALL_DIR/xray x25519)"
  PRIVATE_KEY="$(printf '%s\n' "$KEYS" | awk -F': ' 'tolower($1) ~ /private/ {print $2; exit}')"
  PUBLIC_KEY="$(printf '%s\n' "$KEYS" | awk -F': ' 'tolower($1) ~ /public/ {print $2; exit}')"
fi
[ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ] || { echo 'x25519 key generation failed' >&2; exit 8; }

umask 077
cat > "$TMP/credentials.env" <<EOF
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
SERVER_NAME=$SERVER_NAME
TARGET=$TARGET
PORT=$PORT
EOF
"${SUDO[@]}" install -m 0600 "$TMP/credentials.env" "$ENV_FILE"

cat > "$TMP/xray.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$TARGET",
        "xver": 0,
        "serverNames": ["$SERVER_NAME"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
    "tag": "ireland-bs-in"
  }],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"}
    ]
  }
}
EOF
"$INSTALL_DIR/xray" run -test -config "$TMP/xray.json"
"${SUDO[@]}" install -m 0600 "$TMP/xray.json" "$CONFIG_FILE"

cat > "$TMP/$SERVICE.service" <<EOF
[Unit]
Description=Wesi Aero Ireland BS VLESS REALITY
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/xray run -config $CONFIG_FILE
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" install -m 0644 "$TMP/$SERVICE.service" "/etc/systemd/system/$SERVICE.service"
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now "$SERVICE"
"${SUDO[@]}" systemctl restart "$SERVICE"
"${SUDO[@]}" systemctl is-active --quiet "$SERVICE"

if command -v ufw >/dev/null 2>&1 && "${SUDO[@]}" ufw status 2>/dev/null | grep -q '^Status: active'; then
  "${SUDO[@]}" ufw allow "$PORT/tcp" comment 'Wesi Aero Ireland BS' >/dev/null
fi

PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-178.236.247.194}"
URI="vless://${UUID}@${PUBLIC_HOST}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#%D0%98%D1%80%D0%BB%D0%B0%D0%BD%D0%B4%D0%B8%D1%8F%20%D0%91%D0%A1"
printf '%s\n' "$URI" > "$TMP/client-uri.txt"
"${SUDO[@]}" install -m 0600 "$TMP/client-uri.txt" "$CLIENT_FILE"

cat <<EOF
Wesi Aero node installed:
  name: Ирландия БС
  endpoint: ${PUBLIC_HOST}:${PORT}
  protocol: VLESS + REALITY
  serverName: ${SERVER_NAME}
  publicKey: ${PUBLIC_KEY}
  shortId: ${SHORT_ID}
  client profile: ${CLIENT_FILE} (root-only)
EOF
