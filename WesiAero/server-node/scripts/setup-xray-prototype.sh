#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

XRAY_VLESS_PORT="${WESI_AERO_REALITY_PORT:-8443}"
XRAY_VMESS_PORT="${WESI_AERO_VMESS_PORT:-8444}"
PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-ai-178-236-247-194.nip.io}"
REALITY_SERVER_NAME="${WESI_AERO_REALITY_SERVER_NAME:-www.cloudflare.com}"
REALITY_DEST="${WESI_AERO_REALITY_DEST:-${REALITY_SERVER_NAME}:443}"
CONFIG_DIR="${WESI_AERO_XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_DIR="${WESI_AERO_XRAY_STATE_DIR:-/var/lib/wesi-aero/xray}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

install_dependencies() {
  if need_cmd apt-get; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates openssl jq
  elif need_cmd dnf; then
    dnf install -y curl ca-certificates openssl jq
  elif need_cmd yum; then
    yum install -y curl ca-certificates openssl jq
  else
    echo "Unsupported package manager. Install curl, ca-certificates, openssl and jq first." >&2
    exit 1
  fi
}

install_xray() {
  if need_cmd xray; then
    return
  fi
  local installer
  installer="$(mktemp)"
  trap 'rm -f "$installer"' RETURN
  curl --fail --location --retry 3 --silent --show-error \
    https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
    -o "$installer"
  chmod 700 "$installer"
  bash "$installer" install
}

extract_key() {
  local output="$1"
  local kind="$2"
  case "$kind" in
    private)
      printf '%s\n' "$output" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}'
      ;;
    public)
      printf '%s\n' "$output" | awk -F': *' 'tolower($1) ~ /(public|password)/ {print $2; exit}'
      ;;
  esac
}

install_dependencies
install_xray
mkdir -p "$CONFIG_DIR" "$STATE_DIR"
chmod 700 "$STATE_DIR"

VLESS_UUID_FILE="$STATE_DIR/vless.uuid"
VMESS_UUID_FILE="$STATE_DIR/vmess.uuid"
REALITY_PRIVATE_FILE="$STATE_DIR/reality.private"
REALITY_PUBLIC_FILE="$STATE_DIR/reality.public"
SHORT_ID_FILE="$STATE_DIR/reality.shortid"

if [[ ! -s "$VLESS_UUID_FILE" ]]; then
  xray uuid > "$VLESS_UUID_FILE"
fi
if [[ ! -s "$VMESS_UUID_FILE" ]]; then
  xray uuid > "$VMESS_UUID_FILE"
fi
if [[ ! -s "$REALITY_PRIVATE_FILE" || ! -s "$REALITY_PUBLIC_FILE" ]]; then
  key_output="$(xray x25519)"
  reality_private="$(extract_key "$key_output" private)"
  reality_public="$(extract_key "$key_output" public)"
  if [[ -z "$reality_private" || -z "$reality_public" ]]; then
    echo "Could not parse xray x25519 output:" >&2
    printf '%s\n' "$key_output" >&2
    exit 1
  fi
  printf '%s\n' "$reality_private" > "$REALITY_PRIVATE_FILE"
  printf '%s\n' "$reality_public" > "$REALITY_PUBLIC_FILE"
fi
if [[ ! -s "$SHORT_ID_FILE" ]]; then
  openssl rand -hex 8 > "$SHORT_ID_FILE"
fi
chmod 600 "$STATE_DIR"/*

VLESS_UUID="$(tr -d '[:space:]' < "$VLESS_UUID_FILE")"
VMESS_UUID="$(tr -d '[:space:]' < "$VMESS_UUID_FILE")"
REALITY_PRIVATE="$(tr -d '[:space:]' < "$REALITY_PRIVATE_FILE")"
REALITY_PUBLIC="$(tr -d '[:space:]' < "$REALITY_PUBLIC_FILE")"
SHORT_ID="$(tr -d '[:space:]' < "$SHORT_ID_FILE")"

cat > "$CONFIG_FILE" <<JSON
{
  "log": {
    "access": "none",
    "dnsLog": false,
    "loglevel": "warning"
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": $XRAY_VLESS_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$VLESS_UUID",
            "email": "wesi-vless",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": ["$REALITY_SERVER_NAME"],
          "privateKey": "$REALITY_PRIVATE",
          "shortIds": ["$SHORT_ID"]
        }
      }
    },
    {
      "tag": "vmess-xray",
      "listen": "0.0.0.0",
      "port": $XRAY_VMESS_PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$VMESS_UUID",
            "email": "wesi-vmess",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
JSON
chmod 600 "$CONFIG_FILE"

xray run -test -config "$CONFIG_FILE"
systemctl enable xray
systemctl restart xray
systemctl --no-pager --full status xray | sed -n '1,12p'

if need_cmd ufw && ufw status | grep -q '^Status: active'; then
  ufw allow "${XRAY_VLESS_PORT}/tcp"
  ufw allow "${XRAY_VMESS_PORT}/tcp"
fi

VLESS_URI="vless://${VLESS_UUID}@${PUBLIC_HOST}:${XRAY_VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC}&sid=${SHORT_ID}&type=tcp#Wesi%20Aero%20VLESS"
VMESS_JSON="$(jq -cn \
  --arg host "$PUBLIC_HOST" \
  --arg port "$XRAY_VMESS_PORT" \
  --arg id "$VMESS_UUID" \
  '{v:"2",ps:"Wesi Aero VMess",add:$host,port:$port,id:$id,aid:"0",scy:"auto",net:"tcp",type:"none",host:"",path:"",tls:""}')"
VMESS_URI="vmess://$(printf '%s' "$VMESS_JSON" | base64 -w0)"

CLIENT_DIR="$STATE_DIR/clients"
mkdir -p "$CLIENT_DIR"
chmod 700 "$CLIENT_DIR"
printf '%s\n' "$VLESS_URI" > "$CLIENT_DIR/vless.txt"
printf '%s\n' "$VMESS_URI" > "$CLIENT_DIR/vmess.txt"
chmod 600 "$CLIENT_DIR"/*

cat <<EOF

Wesi Aero Xray prototype is active.
Primary: VLESS + REALITY on ${PUBLIC_HOST}:${XRAY_VLESS_PORT}
Fallback: VMess + Xray on ${PUBLIC_HOST}:${XRAY_VMESS_PORT}

VLESS profile:
${VLESS_URI}

VMess profile:
${VMESS_URI}

Profiles are also stored in:
${CLIENT_DIR}
EOF
