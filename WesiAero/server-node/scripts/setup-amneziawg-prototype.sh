#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

AWG_INTERFACE="${AWG_INTERFACE:-awg0}"
AWG_ENDPOINT_HOST="${AWG_ENDPOINT_HOST:-${WESI_AERO_PUBLIC_HOST:-}}"
AWG_ENDPOINT_PORT="${AWG_ENDPOINT_PORT:-51821}"
AWG_SERVER_ADDRESS="${AWG_SERVER_ADDRESS:-10.78.0.1/24}"
AWG_CLIENT_ADDRESS="${AWG_CLIENT_ADDRESS:-10.78.0.2/32}"
AWG_DNS="${AWG_DNS:-1.1.1.1}"
AWG_CONFIG_DIR="${AWG_CONFIG_DIR:-/etc/amnezia/amneziawg}"
AWG_STATE_DIR="${AWG_STATE_DIR:-/var/lib/wesi-aero/amneziawg}"
AWG_PROFILE_DIR="${WESI_AERO_PROFILE_DIR:-/var/lib/wesi-aero/profiles}"
AWG_GO_COMMIT="${AWG_GO_COMMIT:-1b86b2ae0e493e7ea93f8c1a0f0cb6735b1551f1}"
AWG_TOOLS_COMMIT="${AWG_TOOLS_COMMIT:-ee0f0a9aa34ff0a0da4b3433b9512781cfe02843}"
AWG_GO_REPO="https://github.com/amnezia-vpn/amneziawg-go.git"
AWG_TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"
SERVICE="wesi-aero-amneziawg.service"

[[ -n "$AWG_ENDPOINT_HOST" ]] || { echo "AWG_ENDPOINT_HOST/WESI_AERO_PUBLIC_HOST is required." >&2; exit 1; }
[[ "$AWG_ENDPOINT_PORT" =~ ^[0-9]+$ ]] && (( AWG_ENDPOINT_PORT >= 1 && AWG_ENDPOINT_PORT <= 65535 )) || {
  echo "AWG_ENDPOINT_PORT must be a valid UDP port." >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y git make gcc ca-certificates curl iproute2 iptables openssl >/dev/null

# The current official userspace implementation requires a modern Go toolchain.
# Use the already-installed one when suitable, otherwise install the pinned Go
# release used by Wesi Aero Android CI as well.
GO_VERSION="1.24.13"
current_go=0
if command -v go >/dev/null 2>&1; then
  current_go="$(go env GOVERSION 2>/dev/null | sed -E 's/^go([0-9]+)\.([0-9]+).*/\1\2/' || echo 0)"
fi
if [[ ! "$current_go" =~ ^[0-9]+$ ]] || (( current_go < 124 )); then
  case "$(uname -m)" in
    x86_64|amd64) go_arch=amd64 ;;
    aarch64|arm64) go_arch=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  tmp_go="$(mktemp -d)"
  curl -fsSL --retry 3 "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o "$tmp_go/go.tgz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp_go/go.tgz"
  rm -rf "$tmp_go"
fi
export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
go version | grep -Eq 'go1\.(24|2[5-9]|[3-9][0-9])\.'

install -d -m 700 "$AWG_CONFIG_DIR" "$AWG_STATE_DIR"
install -d -m 750 "$AWG_PROFILE_DIR"

build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT

git clone -q "$AWG_GO_REPO" "$build_root/amneziawg-go"
git -C "$build_root/amneziawg-go" checkout -q "$AWG_GO_COMMIT"
make -C "$build_root/amneziawg-go" >/dev/null
make -C "$build_root/amneziawg-go" install PREFIX=/usr/local >/dev/null

git clone -q "$AWG_TOOLS_REPO" "$build_root/amneziawg-tools"
git -C "$build_root/amneziawg-tools" checkout -q "$AWG_TOOLS_COMMIT"
make -C "$build_root/amneziawg-tools/src" >/dev/null
make -C "$build_root/amneziawg-tools/src" install PREFIX=/usr/local >/dev/null

command -v amneziawg-go >/dev/null
command -v awg >/dev/null
command -v awg-quick >/dev/null

SECRETS="$AWG_STATE_DIR/secrets.env"
umask 077
if [[ ! -s "$SECRETS" ]]; then
  SERVER_PRIVATE="$(awg genkey)"
  SERVER_PUBLIC="$(printf '%s' "$SERVER_PRIVATE" | awg pubkey)"
  CLIENT_PRIVATE="$(awg genkey)"
  CLIENT_PUBLIC="$(printf '%s' "$CLIENT_PRIVATE" | awg pubkey)"

  # Keep packet sizes well below common mobile MTUs. J* is client-side noise;
  # S*/H* must stay identical between server and client.
  AWG_JC=4
  AWG_JMIN=40
  AWG_JMAX=70
  AWG_S1=$(( 32 + $(od -An -N1 -tu1 /dev/urandom) % 65 ))
  AWG_S2=$(( 32 + $(od -An -N1 -tu1 /dev/urandom) % 65 ))
  AWG_S3=0
  AWG_S4=0
  AWG_H1=$(( 100000000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 800000000 ))
  AWG_H2=$(( 1100000000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 800000000 ))
  AWG_H3=$(( 2200000000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 700000000 ))
  AWG_H4=$(( 3300000000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 700000000 ))

  cat > "$SECRETS" <<EOF
SERVER_PRIVATE=$SERVER_PRIVATE
SERVER_PUBLIC=$SERVER_PUBLIC
CLIENT_PRIVATE=$CLIENT_PRIVATE
CLIENT_PUBLIC=$CLIENT_PUBLIC
AWG_JC=$AWG_JC
AWG_JMIN=$AWG_JMIN
AWG_JMAX=$AWG_JMAX
AWG_S1=$AWG_S1
AWG_S2=$AWG_S2
AWG_S3=$AWG_S3
AWG_S4=$AWG_S4
AWG_H1=$AWG_H1
AWG_H2=$AWG_H2
AWG_H3=$AWG_H3
AWG_H4=$AWG_H4
EOF
fi
chmod 600 "$SECRETS"
# shellcheck disable=SC1090
source "$SECRETS"

WAN_INTERFACE="${AWG_WAN_INTERFACE:-$(ip route show default 0.0.0.0/0 | awk '{print $5; exit}')}"
[[ -n "$WAN_INTERFACE" ]] || { echo "Unable to detect WAN interface." >&2; exit 1; }

cat >/etc/sysctl.d/99-wesi-aero-amneziawg.conf <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL
sysctl --system >/dev/null

SERVER_CONFIG="$AWG_CONFIG_DIR/${AWG_INTERFACE}.conf"
CLIENT_CONFIG="$AWG_STATE_DIR/client.conf"
cat > "$SERVER_CONFIG" <<EOF
[Interface]
Address = $AWG_SERVER_ADDRESS
ListenPort = $AWG_ENDPOINT_PORT
PrivateKey = $SERVER_PRIVATE
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
Table = off
PostUp = iptables -C INPUT -p udp --dport $AWG_ENDPOINT_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $AWG_ENDPOINT_PORT -j ACCEPT; iptables -C FORWARD -i %i -j ACCEPT 2>/dev/null || iptables -A FORWARD -i %i -j ACCEPT; iptables -C FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -C POSTROUTING -o $WAN_INTERFACE -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $WAN_INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $AWG_ENDPOINT_PORT -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -o $WAN_INTERFACE -j MASQUERADE 2>/dev/null || true

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = $AWG_CLIENT_ADDRESS
EOF
chmod 600 "$SERVER_CONFIG"

CLIENT_IP="${AWG_CLIENT_ADDRESS%/*}"
cat > "$CLIENT_CONFIG" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_IP/32
DNS = $AWG_DNS
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $AWG_ENDPOINT_HOST:$AWG_ENDPOINT_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 "$CLIENT_CONFIG"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "$AWG_ENDPOINT_PORT/udp" comment 'Wesi Aero AmneziaWG' >/dev/null
fi

cat > "/etc/systemd/system/$SERVICE" <<EOF
[Unit]
Description=Wesi Aero AmneziaWG relay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=WG_QUICK_USERSPACE_IMPLEMENTATION=/usr/local/bin/amneziawg-go
ExecStart=/usr/local/bin/awg-quick up $AWG_INTERFACE
ExecStop=/usr/local/bin/awg-quick down $AWG_INTERFACE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
systemctl restart "$SERVICE"
systemctl is-active --quiet "$SERVICE"
awg show "$AWG_INTERFACE" >/dev/null
ss -lun | grep -q ":$AWG_ENDPOINT_PORT "
iptables -C INPUT -p udp --dport "$AWG_ENDPOINT_PORT" -j ACCEPT >/dev/null 2>&1

PROFILE="$AWG_PROFILE_DIR/_default.wesi-relay.amneziawg.json"
jq -n --arg protocol amneziawg --rawfile clientConfig "$CLIENT_CONFIG" \
  '{protocol:$protocol, clientConfig:$clientConfig}' > "$PROFILE"
if getent group wesi-aero >/dev/null 2>&1; then
  chown root:wesi-aero "$PROFILE"
  chmod 640 "$PROFILE"
else
  chmod 600 "$PROFILE"
fi

jq -e '.protocol == "amneziawg" and (.clientConfig | contains("Jc =") and contains("H4 ="))' "$PROFILE" >/dev/null

echo "Wesi Aero AmneziaWG gateway active on UDP $AWG_ENDPOINT_PORT ($AWG_INTERFACE)."
