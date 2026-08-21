#!/usr/bin/env bash
set -Eeuo pipefail

: "${AERO_HOST:?AERO_HOST is required}"
: "${AI_HOST:?AI_HOST is required}"
: "${EXPECTED_RELAY_IP:?EXPECTED_RELAY_IP is required}"
: "${RELAY_SSH_HOST:?RELAY_SSH_HOST is required}"
: "${RELAY_SSH_USER:?RELAY_SSH_USER is required}"
: "${RELAY_SSH_KEY:?RELAY_SSH_KEY is required}"

WORK=/tmp/wesi-aero-live-probe
rm -rf "$WORK"
mkdir -p "$WORK" "$HOME/.ssh"
chmod 700 "$WORK" "$HOME/.ssh"
printf '%s\n' "$RELAY_SSH_KEY" > "$HOME/.ssh/wesi_aero_relay"
chmod 600 "$HOME/.ssh/wesi_aero_relay"
if [[ -n "${RELAY_SSH_KNOWN_HOSTS:-}" ]]; then
  printf '%s\n' "$RELAY_SSH_KNOWN_HOSTS" > "$HOME/.ssh/wesi_aero_known_hosts"
else
  ssh-keyscan -H "$RELAY_SSH_HOST" > "$HOME/.ssh/wesi_aero_known_hosts" 2>/dev/null
fi
chmod 600 "$HOME/.ssh/wesi_aero_known_hosts"
SSH=(-i "$HOME/.ssh/wesi_aero_relay" -o BatchMode=yes -o UserKnownHostsFile="$HOME/.ssh/wesi_aero_known_hosts")

resolved="$(getent ahostsv4 "$AERO_HOST" | awk '{print $1; exit}')"
[[ "$resolved" == "$EXPECTED_RELAY_IP" ]] || {
  echo "Aero DNS mismatch: $resolved != $EXPECTED_RELAY_IP" >&2
  exit 1
}
curl -fsS --max-time 15 "https://$AI_HOST/health" >/dev/null

# Some VPS providers use a different IPv4 address for outbound NAT than the
# public address accepting inbound connections. A tunnel is correct when its
# egress matches the egress observed directly from this VPS.
RELAY_EGRESS_IP="$(ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" \
  "curl -4fsS --max-time 10 https://v4.ident.me | tr -d '[:space:]'")"
[[ "$RELAY_EGRESS_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
  echo "Unable to determine Relay IPv4 egress: $RELAY_EGRESS_IP" >&2
  exit 1
}
echo "Relay ingress: $EXPECTED_RELAY_IP; observed IPv4 egress: $RELAY_EGRESS_IP"

REMOTE="/tmp/wesi-aero-live-${GITHUB_RUN_ID:-manual}"
ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE'"
scp -r "${SSH[@]}" WesiAero/server-node "$RELAY_SSH_USER@$RELAY_SSH_HOST:$REMOTE/"

ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" \
  "REMOTE='$REMOTE' AERO_HOST='$AERO_HOST' bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail
if [[ "$(id -u)" -eq 0 ]]; then SUDO=(); else SUDO=(sudo -n); fi
chmod +x "$REMOTE/server-node/scripts/"*.sh

"${SUDO[@]}" env \
  WESI_AERO_PUBLIC_HOST="$AERO_HOST" \
  WESI_AERO_REALITY_PORT=8443 \
  WESI_AERO_VMESS_PORT=8444 \
  bash "$REMOTE/server-node/scripts/setup-xray-prototype.sh"

"${SUDO[@]}" env \
  WG_ENDPOINT_HOST="$AERO_HOST" \
  WG_ENDPOINT_PORT=51820 \
  WG_CLIENT_CONFIG=/root/wesi-aero-client.conf \
  bash "$REMOTE/server-node/scripts/setup-wireguard-prototype.sh"

"${SUDO[@]}" env \
  WESI_AERO_PUBLIC_HOST="$AERO_HOST" \
  WESI_AERO_RELAY_PUBLIC_HOST="$AERO_HOST" \
  bash "$REMOTE/server-node/scripts/setup-control-plane-prototype.sh" "$REMOTE/server-node"

"${SUDO[@]}" env WESI_AERO_PUBLIC_HOST="$AERO_HOST" \
  bash "$REMOTE/server-node/scripts/configure-control-plane-https.sh" "$AERO_HOST"

systemctl is-active --quiet xray
systemctl is-active --quiet wg-quick@wg0
systemctl is-active --quiet wesi-aero-control
ss -ltn | grep -q ':8443 '
ss -ltn | grep -q ':8444 '
ss -lun | grep -q ':51820 '
curl -fsS --max-time 10 http://127.0.0.1:8790/healthz >/dev/null
curl -fsS --max-time 20 "https://$AERO_HOST/healthz" >/dev/null
REMOTE_SCRIPT

scp "${SSH[@]}" \
  "$RELAY_SSH_USER@$RELAY_SSH_HOST:/var/lib/wesi-aero/xray/clients/vless-client.json" \
  "$WORK/vless-client.json"
scp "${SSH[@]}" \
  "$RELAY_SSH_USER@$RELAY_SSH_HOST:/var/lib/wesi-aero/xray/clients/vmess-client.json" \
  "$WORK/vmess-client.json"
ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" \
  'if [[ "$(id -u)" -eq 0 ]]; then cat /root/wesi-aero-client.conf; else sudo -n cat /root/wesi-aero-client.conf; fi' \
  > "$WORK/wireguard.conf"
chmod 600 "$WORK"/*

sudo apt-get update -y >/dev/null
sudo apt-get install -y wireguard-tools curl ca-certificates >/dev/null
curl -fsSL --retry 3 \
  https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
  -o "$WORK/install-xray.sh"
chmod 700 "$WORK/install-xray.sh"
sudo bash "$WORK/install-xray.sh" install --without-geodata >/dev/null
sudo systemctl stop xray 2>/dev/null || true

probe_xray() {
  local name="$1" config="$2" result="$WORK/$1-ip" log="$WORK/$1.log"
  xray run -config "$config" >"$log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 --socks5-hostname 127.0.0.1:10808 \
      https://v4.ident.me >"$result" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  local ip
  ip="$(tr -d '[:space:]' < "$result" 2>/dev/null || true)"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if [[ "$ip" != "$RELAY_EGRESS_IP" ]]; then
    tail -n 80 "$log" >&2 || true
    echo "$name egress mismatch: $ip != VPS egress $RELAY_EGRESS_IP" >&2
    return 1
  fi
  echo "$name external egress verified through VPS: $ip"
}

probe_xray vless "$WORK/vless-client.json"
probe_xray vmess "$WORK/vmess-client.json"

CONF="$WORK/wireguard.conf"
PRIVATE_FILE="$WORK/wg.private"
awk -F' = ' '/^PrivateKey/ {print $2; exit}' "$CONF" > "$PRIVATE_FILE"
chmod 600 "$PRIVATE_FILE"
SERVER_PUBLIC="$(awk -F' = ' '/^PublicKey/ {print $2; exit}' "$CONF")"
ENDPOINT="$(awk -F' = ' '/^Endpoint/ {print $2; exit}' "$CONF")"
CLIENT_ADDRESS="$(awk -F' = ' '/^Address/ {print $2; exit}' "$CONF")"
[[ -n "$SERVER_PUBLIC" && -n "$ENDPOINT" && -n "$CLIENT_ADDRESS" ]] || {
  echo 'WireGuard client profile is incomplete.' >&2
  exit 1
}

echo "WireGuard probe endpoint: $ENDPOINT; client address: $CLIENT_ADDRESS"
cleanup_wg() {
  sudo ip route del 1.1.1.1/32 dev wesiwg 2>/dev/null || true
  sudo ip route del 10.77.0.1/32 dev wesiwg 2>/dev/null || true
  sudo ip link del wesiwg 2>/dev/null || true
}
trap cleanup_wg EXIT
cleanup_wg

sudo ip link add dev wesiwg type wireguard
sudo ip address add "$CLIENT_ADDRESS" dev wesiwg
sudo wg set wesiwg \
  private-key "$PRIVATE_FILE" \
  peer "$SERVER_PUBLIC" \
  endpoint "$ENDPOINT" \
  allowed-ips 10.77.0.1/32,1.1.1.1/32 \
  persistent-keepalive 25
sudo ip link set up dev wesiwg
sudo ip route replace 10.77.0.1/32 dev wesiwg
sudo ip route replace 1.1.1.1/32 dev wesiwg

echo 'WireGuard client interface configured; provoking handshake.'
# ICMP reachability is not a protocol requirement. Send traffic only to cause
# the kernel to initiate a handshake, then inspect WireGuard's own state.
ping -c 1 -W 1 10.77.0.1 >/dev/null 2>&1 || true
handshake=0
for _ in $(seq 1 15); do
  handshake="$(sudo wg show wesiwg latest-handshakes | awk '{print $2; exit}')"
  if [[ "${handshake:-0}" -gt 0 ]]; then
    break
  fi
  ping -c 1 -W 1 10.77.0.1 >/dev/null 2>&1 || true
  sleep 1
done
if [[ "${handshake:-0}" -le 0 ]]; then
  echo 'WireGuard handshake missing after 15 seconds.' >&2
  sudo wg show wesiwg >&2 || true
  ip -4 address show dev wesiwg >&2 || true
  ip -4 route show >&2 || true
  getent ahostsv4 "$AERO_HOST" >&2 || true
  ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" \
    'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo -n"; fi; $SUDO wg show wg0; $SUDO iptables -S INPUT | grep 51820 || true; $SUDO ss -lunp | grep 51820 || true' \
    >&2 || true
  exit 1
fi
echo "WireGuard cryptographic handshake verified at epoch $handshake."

if ! curl -fsS --max-time 20 \
  --connect-to one.one.one.one:443:1.1.1.1:443 \
  https://one.one.one.one/cdn-cgi/trace > "$WORK/wg-trace"; then
  echo 'WireGuard handshake succeeded but routed HTTPS egress failed.' >&2
  sudo wg show wesiwg >&2 || true
  ip route get 1.1.1.1 >&2 || true
  ssh "${SSH[@]}" "$RELAY_SSH_USER@$RELAY_SSH_HOST" \
    'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo -n"; fi; $SUDO sysctl net.ipv4.ip_forward; $SUDO iptables -S FORWARD; $SUDO iptables -t nat -S POSTROUTING' \
    >&2 || true
  exit 1
fi
wg_ip="$(awk -F= '$1=="ip" {print $2}' "$WORK/wg-trace")"
[[ "$wg_ip" == "$RELAY_EGRESS_IP" ]] || {
  echo "WireGuard egress mismatch: $wg_ip != VPS egress $RELAY_EGRESS_IP" >&2
  sudo wg show wesiwg >&2 || true
  exit 1
}
echo "WireGuard handshake and external egress verified through VPS: $wg_ip"
cleanup_wg
trap - EXIT

curl -fsS --max-time 20 "https://$AERO_HOST/healthz" | jq -e '.status == "ok"' >/dev/null
curl -fsS --max-time 20 "https://$AERO_HOST/v1/catalog" \
  | jq -e '(.paymentMethods | length) == 0 and (.servers[] | select(.id == "wesi-relay") | (.protocols | index("vless-reality")) != null and (.protocols | index("vmess-xray")) != null and (.protocols | index("amneziawg")) != null)' >/dev/null
curl -fsS --max-time 20 "https://$AI_HOST/health" >/dev/null

echo 'Public Wesi Aero control plane healthy, payments disabled, Wesi AI preserved.'
rm -rf "$WORK"
echo "Wesi Aero live VPN prototype verified: VLESS, VMess, WireGuard and HTTPS control plane."
