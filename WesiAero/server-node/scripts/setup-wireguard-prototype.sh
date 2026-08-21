#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_ENDPOINT_HOST="${WG_ENDPOINT_HOST:-}"
WG_ENDPOINT_PORT="${WG_ENDPOINT_PORT:-51820}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.77.0.1/24}"
WG_CLIENT_ADDRESS="${WG_CLIENT_ADDRESS:-10.77.0.2/32}"
WG_DNS="${WG_DNS:-1.1.1.1}"
WG_CONFIG_DIR="${WG_CONFIG_DIR:-/etc/wireguard}"
WG_CLIENT_CONFIG="${WG_CLIENT_CONFIG:-/root/wesi-aero-client.conf}"

if [[ -z "$WG_ENDPOINT_HOST" ]]; then
  echo "WG_ENDPOINT_HOST is required (public IP or DNS name of this VPS)." >&2
  exit 1
fi
if ! [[ "$WG_ENDPOINT_PORT" =~ ^[0-9]+$ ]] || (( WG_ENDPOINT_PORT < 1 || WG_ENDPOINT_PORT > 65535 )); then
  echo "WG_ENDPOINT_PORT must be a valid UDP port." >&2
  exit 1
fi

if ! command -v wg >/dev/null 2>&1 || ! command -v wg-quick >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y wireguard-tools iptables
  else
    echo "WireGuard tools are missing and this prototype installer currently supports apt-based Linux hosts." >&2
    exit 1
  fi
fi

WAN_INTERFACE="${WG_WAN_INTERFACE:-$(ip route show default 0.0.0.0/0 | awk '{print $5; exit}')}"
if [[ -z "$WAN_INTERFACE" ]]; then
  echo "Unable to detect the public network interface. Set WG_WAN_INTERFACE explicitly." >&2
  exit 1
fi

install -d -m 700 "$WG_CONFIG_DIR"
umask 077
SERVER_PRIVATE="$WG_CONFIG_DIR/${WG_INTERFACE}.server.key"
SERVER_PUBLIC="$WG_CONFIG_DIR/${WG_INTERFACE}.server.pub"
CLIENT_PRIVATE="$WG_CONFIG_DIR/${WG_INTERFACE}.client.key"
CLIENT_PUBLIC="$WG_CONFIG_DIR/${WG_INTERFACE}.client.pub"

if [[ ! -s "$SERVER_PRIVATE" ]]; then
  wg genkey | tee "$SERVER_PRIVATE" | wg pubkey > "$SERVER_PUBLIC"
fi
if [[ ! -s "$CLIENT_PRIVATE" ]]; then
  wg genkey | tee "$CLIENT_PRIVATE" | wg pubkey > "$CLIENT_PUBLIC"
fi
chmod 600 "$SERVER_PRIVATE" "$SERVER_PUBLIC" "$CLIENT_PRIVATE" "$CLIENT_PUBLIC"

SERVER_PRIVATE_KEY="$(<"$SERVER_PRIVATE")"
SERVER_PUBLIC_KEY="$(<"$SERVER_PUBLIC")"
CLIENT_PRIVATE_KEY="$(<"$CLIENT_PRIVATE")"
CLIENT_PUBLIC_KEY="$(<"$CLIENT_PUBLIC")"

cat >/etc/sysctl.d/99-wesi-aero-wireguard.conf <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL
sysctl --system >/dev/null

# Open WireGuard explicitly on hosts using UFW. The wg-quick PostUp rule below
# also handles hosts that filter INPUT directly through iptables/nftables.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "$WG_ENDPOINT_PORT/udp" comment 'Wesi Aero WireGuard' >/dev/null
fi

SERVER_CONFIG="$WG_CONFIG_DIR/${WG_INTERFACE}.conf"
if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}.service" 2>/dev/null; then
  systemctl stop "wg-quick@${WG_INTERFACE}.service"
elif ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
  wg-quick down "$SERVER_CONFIG" || true
fi

cat >"$SERVER_CONFIG" <<EOF
[Interface]
Address = $WG_SERVER_ADDRESS
ListenPort = $WG_ENDPOINT_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -I INPUT -p udp --dport $WG_ENDPOINT_PORT -j ACCEPT; iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o $WAN_INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_ENDPOINT_PORT -j ACCEPT; iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $WAN_INTERFACE -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_ADDRESS
EOF
chmod 600 "$SERVER_CONFIG"

CLIENT_IP="${WG_CLIENT_ADDRESS%/*}"
cat >"$WG_CLIENT_CONFIG" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = $WG_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $WG_ENDPOINT_HOST:$WG_ENDPOINT_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 "$WG_CLIENT_CONFIG"

systemctl enable "wg-quick@${WG_INTERFACE}.service" >/dev/null
systemctl restart "wg-quick@${WG_INTERFACE}.service"

if ! systemctl is-active --quiet "wg-quick@${WG_INTERFACE}.service"; then
  echo "WireGuard service failed to start." >&2
  systemctl --no-pager --full status "wg-quick@${WG_INTERFACE}.service" || true
  exit 1
fi

if ! wg show "$WG_INTERFACE" >/dev/null 2>&1; then
  echo "WireGuard interface is not available after startup." >&2
  exit 1
fi

iptables -C INPUT -p udp --dport "$WG_ENDPOINT_PORT" -j ACCEPT >/dev/null 2>&1 || {
  echo "WireGuard UDP firewall rule is missing after startup." >&2
  exit 1
}

echo "Wesi Aero WireGuard gateway is active."
echo "Interface: $WG_INTERFACE"
echo "UDP endpoint: $WG_ENDPOINT_HOST:$WG_ENDPOINT_PORT"
echo "Client profile: $WG_CLIENT_CONFIG"
echo "Import that profile into Wesi Aero on Android, grant the Android VPN permission, then connect."
