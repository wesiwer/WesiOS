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

# When the dedicated restrictive transport service is active, the VMess lease
# uses standards-compliant TLS/443 + WebSocket on the Wesi-owned hostname. The
# old raw VMess listener remains available server-side as a compatibility path.
if [[ -s "$STATE_DIR/singbox/clients/vmess-ws443.txt" ]]; then
  write_profile vmess "$STATE_DIR/singbox/clients/vmess-ws443.txt" vmess
fi

# Standard WireGuard remains its own profile on UDP 51820.
if [[ -s /root/wesi-aero-client.conf ]]; then
  write_profile wireguard /root/wesi-aero-client.conf wireguard
fi

if write_profile trojan "$STATE_DIR/singbox/clients/trojan.txt" trojan; then protocols+=(trojan); fi
if write_profile shadowsocks "$STATE_DIR/singbox/clients/shadowsocks.txt" shadowsocks; then protocols+=(shadowsocks); fi
if write_profile hysteria2 "$STATE_DIR/singbox/clients/hysteria2.txt" hysteria2; then protocols+=(hysteria2); fi
if write_profile tuic "$STATE_DIR/singbox/clients/tuic.txt" tuic; then protocols+=(tuic); fi

# Never advertise AmneziaWG merely because the UI understands the protocol.
# It becomes live only after the real userspace AWG interface generated a
# profile containing its obfuscation parameters.
AWG_PROFILE="$PROFILE_DIR/_default.wesi-relay.amneziawg.json"
if [[ -s "$AWG_PROFILE" ]] && jq -e '
  .protocol == "amneziawg" and
  (.clientConfig | contains("Jc =") and contains("Jmin =") and contains("Jmax =") and contains("H4 ="))
' "$AWG_PROFILE" >/dev/null; then
  chown root:"$SERVICE_USER" "$AWG_PROFILE"
  chmod 640 "$AWG_PROFILE"
  protocols+=(amneziawg)
fi

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
    tags:["relay","xray","sing-box","wireguard","amneziawg","https443","prototype"],
    notes:"Multi-engine Wesi Relay with Wesi-owned TLS/443 restrictive-network transports.",
    transportConfig:{
      defaultProtocol:"vmess",
      fallbackProtocol:"vless-reality",
      realityPort:8443,
      vmessPort:8444,
      trojanPort:8445,
      shadowsocksPort:8388,
      hysteria2Port:8446,
      tuicPort:8447,
      wireGuardPort:51820,
      amneziaWgPort:51821,
      engines:["sing-box","xray","native"],
      restrictiveNetwork:{
        enabled:true,
        publicPort:443,
        tlsVersions:["TLSv1.2","TLSv1.3"],
        hostname:$host,
        primary:{protocol:"vmess",transport:"websocket"},
        candidates:["websocket","grpc","http2"],
        domainFronting:false,
        thirdPartyCdn:false,
        edgePolicy:"wesi-owned-or-explicitly-authorized"
      }
    }
  }')"

curl -fsS \
  -X PUT \
  -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
  -H 'content-type: application/json' \
  --data "$payload" \
  http://127.0.0.1:8790/v1/admin/servers/wesi-relay >/dev/null

# Public catalog intentionally omits detailed transportConfig. Clients only need
# the public capability tag and protocol list; the exact internal policy stays
# in the authenticated admin snapshot. This prevents accidental publication of
# future transport fields if an administrator adds sensitive backend metadata.
catalog="$(curl -fsS http://127.0.0.1:8790/v1/catalog)"
for protocol in "${protocols[@]}"; do
  jq -e --arg p "$protocol" '.servers[] | select(.id=="wesi-relay") | (.protocols | index($p)) != null' <<<"$catalog" >/dev/null
done
jq -e '
  .servers[] | select(.id=="wesi-relay") |
  (.tags | index("https443")) != null and
  (.transportConfig == null)
' <<<"$catalog" >/dev/null

admin_snapshot="$(curl -fsS \
  -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
  http://127.0.0.1:8790/v1/admin/snapshot)"
jq -e --arg host "$PUBLIC_HOST" '
  .servers[] | select(.id=="wesi-relay") |
  .transportConfig.defaultProtocol == "vmess" and
  .transportConfig.restrictiveNetwork.enabled == true and
  .transportConfig.restrictiveNetwork.publicPort == 443 and
  .transportConfig.restrictiveNetwork.hostname == $host and
  .transportConfig.restrictiveNetwork.primary.transport == "websocket" and
  .transportConfig.restrictiveNetwork.domainFronting == false and
  .transportConfig.restrictiveNetwork.thirdPartyCdn == false
' <<<"$admin_snapshot" >/dev/null

echo "Wesi Relay catalog synchronized: ${protocols[*]}"
