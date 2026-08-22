#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

SOURCE_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
RELAY_HOST="${WESI_AERO_RELAY_PUBLIC_HOST:-$PUBLIC_HOST}"
INSTALL_DIR="${WESI_AERO_INSTALL_DIR:-/opt/wesi-aero/server-node}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero}"
DATA_DIR="$STATE_DIR/control"
PROFILE_DIR="$STATE_DIR/profiles"
ENV_DIR="/etc/wesi-aero"
ENV_FILE="$ENV_DIR/control.env"
SERVICE_USER="wesi-aero"
SERVICE_NAME="wesi-aero-control.service"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

install_base_dependencies() {
  if need_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl ca-certificates openssl jq xz-utils
  else
    echo "Prototype control-plane installer currently supports Debian/Ubuntu." >&2
    exit 1
  fi
}

install_node24() {
  local major=0
  if need_cmd node; then
    major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
  fi
  if (( major >= 24 )); then
    return
  fi

  local version package_arch archive tmp
  case "$(uname -m)" in
    x86_64|amd64) package_arch=x64 ;;
    aarch64|arm64) package_arch=arm64 ;;
    *) echo "Unsupported CPU architecture for Node.js 24: $(uname -m)" >&2; exit 1 ;;
  esac
  version="$(curl -fsSL https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt | awk -v arch="linux-${package_arch}.tar.xz" '$2 ~ arch"$" {sub(/node-/,"",$2); sub("-"arch,"",$2); print $2; exit}')"
  [[ "$version" =~ ^v24\.[0-9]+\.[0-9]+$ ]] || {
    echo "Unable to resolve latest Node.js 24 release." >&2
    exit 1
  }
  archive="node-${version}-linux-${package_arch}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL --retry 3 "https://nodejs.org/dist/${version}/${archive}.tar.xz" -o "$tmp/node.tar.xz"
  tar -xJf "$tmp/node.tar.xz" -C "$tmp"
  cp -a "$tmp/$archive/." /usr/local/
  hash -r
  node --version | grep -q '^v24\.'
}

install_base_dependencies
install_node24

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

install -d -m 755 "$INSTALL_DIR" "$ENV_DIR"
install -d -m 750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$DATA_DIR"
install -d -m 750 -o root -g "$SERVICE_USER" "$PROFILE_DIR"

rm -rf "$INSTALL_DIR"/*
cp -a "$SOURCE_DIR"/. "$INSTALL_DIR"/
chown -R root:root "$INSTALL_DIR"
chmod -R o-w "$INSTALL_DIR"

if [[ ! -s "$ENV_FILE" ]]; then
  ADMIN_TOKEN="$(openssl rand -hex 32)"
  MASTER_KEY="$(openssl rand -hex 32)"
  cat > "$ENV_FILE" <<EOF
WESI_AERO_HOST=127.0.0.1
WESI_AERO_PORT=8790
WESI_AERO_DATABASE=$DATA_DIR/wesi-aero.db
WESI_AERO_PROFILE_DIR=$PROFILE_DIR
WESI_AERO_ADMIN_TOKEN=$ADMIN_TOKEN
WESI_AERO_MASTER_KEY=$MASTER_KEY
WESI_AERO_PUBLIC_BASE_URL=https://$PUBLIC_HOST
WESI_AERO_PAYMENT_RETURN_URL=https://$PUBLIC_HOST/v1/payment-return
WESI_AERO_ALLOW_MOCK_PAYMENTS=false
WESI_AERO_CRYPTO_PAY_TESTNET=true
WESI_AERO_SEED_DEMO=true
WESI_AERO_RELAY_PUBLIC_HOST=$RELAY_HOST
WESI_AERO_TECHNICAL_LOGS=false
EOF
  chmod 600 "$ENV_FILE"
fi

# Existing prototype installations may have been created while technical API
# request logging defaulted to on. Migrate them to privacy-by-default without
# touching any secret values in the environment file.
if grep -q '^WESI_AERO_TECHNICAL_LOGS=' "$ENV_FILE"; then
  sed -i 's/^WESI_AERO_TECHNICAL_LOGS=.*/WESI_AERO_TECHNICAL_LOGS=false/' "$ENV_FILE"
else
  printf 'WESI_AERO_TECHNICAL_LOGS=false\n' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

write_profile() {
  local protocol="$1" source="$2" target="$3"
  [[ -s "$source" ]] || {
    echo "Missing generated client profile: $source" >&2
    exit 1
  }
  jq -n --arg protocol "$protocol" --rawfile clientConfig "$source" \
    '{protocol:$protocol, clientConfig:$clientConfig}' > "$target"
  chown root:"$SERVICE_USER" "$target"
  chmod 640 "$target"
}

write_profile \
  "vless-reality" \
  "/var/lib/wesi-aero/xray/clients/vless.txt" \
  "$PROFILE_DIR/_default.wesi-relay.vless-reality.json"
write_profile \
  "vmess-xray" \
  "/var/lib/wesi-aero/xray/clients/vmess.txt" \
  "$PROFILE_DIR/_default.wesi-relay.vmess-xray.json"

# Standard WireGuard and AmneziaWG are different wire protocols once AWG
# obfuscation is enabled. Never publish a WireGuard config under an AmneziaWG
# filename or silently substitute one for the other.
write_profile \
  "wireguard" \
  "/root/wesi-aero-client.conf" \
  "$PROFILE_DIR/_default.wesi-relay.wireguard.json"
if [[ -s "$STATE_DIR/amneziawg/client.conf" ]]; then
  write_profile \
    "amneziawg" \
    "$STATE_DIR/amneziawg/client.conf" \
    "$PROFILE_DIR/_default.wesi-relay.amneziawg.json"
fi

NODE_BIN="$(command -v node)"
cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Wesi Aero Control Plane
After=network-online.target xray.service wg-quick@wg0.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$NODE_BIN src/index.mjs
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$STATE_DIR
LockPersonality=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"

for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:8790/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
if ! curl -fsS --max-time 5 http://127.0.0.1:8790/healthz | jq -e '.status == "ok"' >/dev/null; then
  systemctl --no-pager --full status "$SERVICE_NAME" || true
  journalctl -u "$SERVICE_NAME" -n 100 --no-pager || true
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Payment is intentionally absent from the working VPN prototype. Disable every
# catalog payment method, including the seed mock provider, while keeping the
# implementation available for the later billing stage.
for provider in mock yookassa crypto_pay; do
  label="Disabled in VPN prototype"
  curl -fsS \
    -X PUT \
    -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
    -H 'content-type: application/json' \
    --data "{\"enabled\":false,\"testMode\":true,\"publicConfig\":{\"label\":\"$label\"}}" \
    "http://127.0.0.1:8790/v1/admin/payment-settings/$provider" \
    >/dev/null
done

# Create one long-lived prototype license without printing the secret. This is
# server-side only and replaces the payment step for the current prototype.
PROTOTYPE_LICENSE_FILE="$STATE_DIR/prototype-license.key"
if [[ ! -s "$PROTOTYPE_LICENSE_FILE" ]]; then
  response="$(curl -fsS \
    -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
    -H 'content-type: application/json' \
    --data '{"planId":"aero-flex","ipMode":"shared","deviceLimit":5,"durationDays":365,"note":"Wesi Aero prototype access"}' \
    http://127.0.0.1:8790/v1/admin/licenses)"
  key="$(printf '%s' "$response" | jq -r '.key // empty')"
  [[ ${#key} -ge 16 ]] || {
    echo "Control plane did not issue a prototype license." >&2
    exit 1
  }
  printf '%s\n' "$key" > "$PROTOTYPE_LICENSE_FILE"
  chmod 600 "$PROTOTYPE_LICENSE_FILE"
fi

curl -fsS --max-time 5 http://127.0.0.1:8790/v1/catalog \
  | jq -e '(.paymentMethods | length) == 0 and (.servers[] | select(.id == "wesi-relay") | (.protocols | index("vless-reality")) != null and (((.protocols | index("vmess")) != null) or ((.protocols | index("vmess-xray")) != null)) and (.protocols | index("wireguard")) != null)' \
  >/dev/null

echo "Wesi Aero control plane is active on 127.0.0.1:8790."
echo "Public facade target: https://$PUBLIC_HOST"
echo "Payment providers are disabled for the VPN prototype."
