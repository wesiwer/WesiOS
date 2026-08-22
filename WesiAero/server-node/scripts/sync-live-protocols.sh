#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This synchronizer must run as root." >&2
  exit 1
fi

PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero}"
PROFILE_DIR="$STATE_DIR/profiles"
ENV_FILE="/etc/wesi-aero/control.env"
SERVICE_USER="wesi-aero"

[[ -s "$ENV_FILE" ]] || { echo "Wesi Aero control env is missing." >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${WESI_AERO_ADMIN_TOKEN:?WESI_AERO_ADMIN_TOKEN is missing}"

install -d -m 750 -o root -g "$SERVICE_USER" "$PROFILE_DIR"

write_profile() {
  local protocol="$1" source="$2" target="$PROFILE_DIR/_default.wesi-relay.$3.json"
  [[ -s "$source" ]] || return 1
  jq -n --arg protocol "$protocol" --rawfile clientConfig "$source" \
    '{protocol:$protocol,clientConfig:$clientConfig}' > "$target"
  chown root:"$SERVICE_USER" "$target"
  chmod 640 "$target"
}

protocols=(vless-reality vmess wireguard)

# Correct the prototype naming: this is standard WireGuard, not real AmneziaWG.
if [[ -s /root/wesi-aero-client.conf ]]; then
  write_profile wireguard /root/wesi-aero-client.conf wireguard
fi

if write_profile trojan "$STATE_DIR/singbox/clients/trojan.txt" trojan; then protocols+=(trojan); fi
if write_profile shadowsocks "$STATE_DIR/singbox/clients/shadowsocks.txt" shadowsocks; then protocols+=(shadowsocks); fi
if write_profile hysteria2 "$STATE_DIR/singbox/clients/hysteria2.txt" hysteria2; then protocols+=(hysteria2); fi
if write_profile tuic "$STATE_DIR/singbox/clients/tuic.txt" tuic; then protocols+=(tuic); fi

protocol_json="$(printf '%s\n' "${protocols[@]}" | jq -R . | jq -s .)"
payload="$(jq -n \
  --arg host "$PUBLIC_HOST" \
  --argjson protocols "$protocol_json" \
  '{
    displayName:"Wesi Relay",
    city:"Wesi Relay",
    country:"Foreign VPS",
    countryCode:"XX",
    endpoint:($host+":8443"),
    protocols:$protocols,
    load:0.05,
    online:true,
    recommended:true,
    capacity:500,
    tags:["relay","xray","sing-box","wireguard","prototype"],
    notes:"Multi-engine Wesi Relay: sing-box, Xray and WireGuard.",
    transportConfig:{
      defaultProtocol:"vless-reality",
      fallbackProtocol:"wireguard",
      realityPort:8443,
      vmessPort:8444,
      trojanPort:8445,
      shadowsocksPort:8388,
      hysteria2Port:8446,
      tuicPort:8447,
      wireGuardPort:51820,
      engines:["sing-box","xray","native"]
    }
  }')"

curl -fsS \
  -X PUT \
  -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
  -H 'content-type: application/json' \
  --data "$payload" \
  http://127.0.0.1:8790/v1/admin/servers/wesi-relay >/dev/null

catalog="$(curl -fsS http://127.0.0.1:8790/v1/catalog)"
for protocol in "${protocols[@]}"; do
  jq -e --arg p "$protocol" '.servers[] | select(.id=="wesi-relay") | (.protocols | index($p)) != null' <<<"$catalog" >/dev/null
 done

echo "Wesi Relay catalog synchronized: ${protocols[*]}"
