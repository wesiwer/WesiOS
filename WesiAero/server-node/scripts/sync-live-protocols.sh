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
PROBE_FILE="${WESI_AERO_RESTRICTIVE_RESULT_FILE:-/tmp/wesi-aero-restrictive-probe.json}"

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

probe='{"websocket":true,"grpc":false,"http2":false}'
if [[ -s "$PROBE_FILE" ]] && jq -e '
  (.websocket|type)=="boolean" and (.grpc|type)=="boolean" and (.http2|type)=="boolean"
' "$PROBE_FILE" >/dev/null 2>&1; then
  probe="$(cat "$PROBE_FILE")"
fi
WS_VERIFIED="$(jq -r '.websocket' <<<"$probe")"
GRPC_VERIFIED="$(jq -r '.grpc' <<<"$probe")"
HTTP2_VERIFIED="$(jq -r '.http2' <<<"$probe")"
[[ "$WS_VERIFIED" == true ]] || {
  echo "Refusing to publish restrictive VMess: WebSocket/TLS/443 is not verified." >&2
  exit 1
}

automatic_transports='["websocket"]'
if [[ "$GRPC_VERIFIED" == true ]]; then
  automatic_transports='["websocket","grpc"]'
fi
server_verified_transports="$(jq -c '[to_entries[] | select(.value == true) | .key]' <<<"$probe")"
failed_transports="$(jq -c '[to_entries[] | select(.value == false) | .key]' <<<"$probe")"

write_restrictive_vmess_profile() {
  local source="$STATE_DIR/singbox/clients/vmess-ws443.txt"
  local uuid_file="$STATE_DIR/singbox/restrictive-vmess.uuid"
  local target="$PROFILE_DIR/_default.wesi-relay.vmess.json"
  [[ -s "$source" && -s "$uuid_file" ]] || return 1

  local uuid sing_config grpc
  uuid="$(tr -d '[:space:]' < "$uuid_file")"
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || {
    echo "Invalid restrictive VMess identity." >&2
    return 1
  }
  grpc=false
  [[ "$GRPC_VERIFIED" == true ]] && grpc=true
  sing_config="$(mktemp)"
  trap 'rm -f "$sing_config"' RETURN

  # One Android sing-box TUN owns both verified TCP/443 transports. urltest
  # performs health selection inside the existing backend, so WS -> gRPC
  # failover does not tear down/recreate VpnService or race for the platform TUN.
  jq -n \
    --arg host "$PUBLIC_HOST" \
    --arg uuid "$uuid" \
    --argjson grpc "$grpc" \
    '{
      log:{level:"warn",timestamp:true},
      dns:{
        servers:[{type:"tls",tag:"remote-dns",server:"1.1.1.1",detour:"proxy"}],
        strategy:"ipv4_only",
        final:"remote-dns"
      },
      inbounds:[{
        type:"tun",tag:"tun-in",address:["172.19.0.1/30"],mtu:1420,
        auto_route:true,strict_route:true,stack:"mixed"
      }],
      outbounds:(
        [{
          type:"vmess",tag:(if $grpc then "vmess-ws443" else "proxy" end),
          server:$host,server_port:443,uuid:$uuid,security:"auto",alter_id:0,
          tls:{enabled:true,server_name:$host,utls:{enabled:true,fingerprint:"chrome"}},
          transport:{type:"ws",path:"/aero/transport/ws",headers:{Host:$host}}
        }]
        + (if $grpc then [
          {
            type:"vmess",tag:"vmess-grpc443",
            server:$host,server_port:443,uuid:$uuid,security:"auto",alter_id:0,
            tls:{enabled:true,server_name:$host,utls:{enabled:true,fingerprint:"chrome"}},
            transport:{type:"grpc",service_name:"wesi.aero.Transport"}
          },
          {
            type:"urltest",tag:"proxy",
            outbounds:["vmess-ws443","vmess-grpc443"],
            url:"https://example.com/",interval:"30s",tolerance:120,
            idle_timeout:"5m",interrupt_exist_connections:true
          }
        ] else [] end)
        + [{type:"direct",tag:"direct"}]
      ),
      route:{
        rules:[{action:"sniff"},{protocol:"dns",action:"hijack-dns"}],
        default_domain_resolver:"remote-dns",
        auto_detect_interface:true,
        final:"proxy"
      }
    }' > "$sing_config"

  sing-box check -c "$sing_config"
  jq -n \
    --arg protocol vmess \
    --rawfile clientConfig "$source" \
    --rawfile singBoxConfig "$sing_config" \
    '{protocol:$protocol,clientConfig:$clientConfig,singBoxConfig:$singBoxConfig}' > "$target"
  chown root:"$SERVICE_USER" "$target"
  chmod 640 "$target"

  jq -e --argjson grpc "$grpc" '
    .protocol == "vmess" and
    (.clientConfig | startswith("vmess://")) and
    (.singBoxConfig | fromjson | .route.final) == "proxy" and
    (if $grpc then
      (.singBoxConfig | fromjson | [.outbounds[] | select(.type=="urltest" and .tag=="proxy")][0].outbounds) == ["vmess-ws443","vmess-grpc443"]
     else
      (.singBoxConfig | fromjson | [.outbounds[] | select(.tag=="proxy" and .type=="vmess")] | length) == 1
     end)
  ' "$target" >/dev/null
}

protocols=(vless-reality vmess wireguard)

# The live VMess lease is a server-built sing-box profile. WebSocket/TLS/443 is
# mandatory and independently verified; gRPC/TLS/443 is added to the in-core
# selector only when the current deployment probe verified its real data plane.
write_restrictive_vmess_profile

# Standard WireGuard remains its own profile on UDP 51820.
if [[ -s /root/wesi-aero-client.conf ]]; then
  write_profile wireguard /root/wesi-aero-client.conf wireguard
fi

if write_profile trojan "$STATE_DIR/singbox/clients/trojan.txt" trojan; then protocols+=(trojan); fi
if write_profile shadowsocks "$STATE_DIR/singbox/clients/shadowsocks.txt" shadowsocks; then protocols+=(shadowsocks); fi
if write_profile hysteria2 "$STATE_DIR/singbox/clients/hysteria2.txt" hysteria2; then protocols+=(hysteria2); fi
if write_profile tuic "$STATE_DIR/singbox/clients/tuic.txt" tuic; then protocols+=(tuic); fi

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
  --argjson automaticTransports "$automatic_transports" \
  --argjson serverVerifiedTransports "$server_verified_transports" \
  --argjson failedTransports "$failed_transports" \
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
        automaticTransports:$automaticTransports,
        serverVerifiedTransports:$serverVerifiedTransports,
        provisionedTransports:["websocket","grpc","http2"],
        failedTransports:$failedTransports,
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
jq -e --arg host "$PUBLIC_HOST" --argjson automatic "$automatic_transports" '
  .servers[] | select(.id=="wesi-relay") |
  .transportConfig.defaultProtocol == "vmess" and
  .transportConfig.restrictiveNetwork.enabled == true and
  .transportConfig.restrictiveNetwork.publicPort == 443 and
  .transportConfig.restrictiveNetwork.hostname == $host and
  .transportConfig.restrictiveNetwork.primary.transport == "websocket" and
  .transportConfig.restrictiveNetwork.automaticTransports == $automatic and
  .transportConfig.restrictiveNetwork.domainFronting == false and
  .transportConfig.restrictiveNetwork.thirdPartyCdn == false
' <<<"$admin_snapshot" >/dev/null

echo "Wesi Relay catalog synchronized: ${protocols[*]}; automatic TLS/443 transports: $(jq -r 'join(",")' <<<"$automatic_transports")"
