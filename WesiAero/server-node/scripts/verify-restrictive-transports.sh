#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This verifier must run as root." >&2
  exit 1
fi

PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero/singbox}"
UUID_FILE="$STATE_DIR/restrictive-vmess.uuid"
RESULT_FILE="${WESI_AERO_RESTRICTIVE_RESULT_FILE:-/tmp/wesi-aero-restrictive-probe.json}"
[[ -s "$UUID_FILE" ]] || { echo "Restrictive VMess identity is missing." >&2; exit 1; }
command -v sing-box >/dev/null 2>&1 || { echo "sing-box is missing." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is missing." >&2; exit 1; }

RESTRICTIVE_UUID="$(tr -d '[:space:]' < "$UUID_FILE")"

has_listener() {
  local port="$1"
  ss -ltnH | awk -v suffix=":$port" '$4 ~ suffix"$" && $4 ~ /^127\.0\.0\.1:/ {found=1} END {exit(found ? 0 : 1)}'
}

probe() {
  local label="$1" type="$2" detail="$3" socks_port="$4"
  local config log pid=''
  config="$(mktemp)"
  log="$(mktemp)"
  cleanup_probe() {
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" 2>/dev/null || true
    fi
    rm -f "$config" "$log"
  }
  trap cleanup_probe RETURN

  case "$type" in
    ws)
      jq -n --arg host "$PUBLIC_HOST" --arg uuid "$RESTRICTIVE_UUID" --arg path "$detail" --argjson port "$socks_port" '{
        log:{level:"error",timestamp:false},
        inbounds:[{type:"socks",tag:"socks-in",listen:"127.0.0.1",listen_port:$port}],
        outbounds:[
          {type:"vmess",tag:"proxy",server:$host,server_port:443,uuid:$uuid,security:"auto",alter_id:0,
           tls:{enabled:true,server_name:$host},
           transport:{type:"ws",path:$path,headers:{Host:$host}}},
          {type:"direct",tag:"direct"}
        ],
        route:{final:"proxy"}
      }' > "$config"
      ;;
    grpc)
      jq -n --arg host "$PUBLIC_HOST" --arg uuid "$RESTRICTIVE_UUID" --arg service "$detail" --argjson port "$socks_port" '{
        log:{level:"error",timestamp:false},
        inbounds:[{type:"socks",tag:"socks-in",listen:"127.0.0.1",listen_port:$port}],
        outbounds:[
          {type:"vmess",tag:"proxy",server:$host,server_port:443,uuid:$uuid,security:"auto",alter_id:0,
           tls:{enabled:true,server_name:$host},
           transport:{type:"grpc",service_name:$service}},
          {type:"direct",tag:"direct"}
        ],
        route:{final:"proxy"}
      }' > "$config"
      ;;
    http)
      jq -n --arg host "$PUBLIC_HOST" --arg uuid "$RESTRICTIVE_UUID" --arg path "$detail" --argjson port "$socks_port" '{
        log:{level:"error",timestamp:false},
        inbounds:[{type:"socks",tag:"socks-in",listen:"127.0.0.1",listen_port:$port}],
        outbounds:[
          {type:"vmess",tag:"proxy",server:$host,server_port:443,uuid:$uuid,security:"auto",alter_id:0,
           tls:{enabled:true,server_name:$host},
           transport:{type:"http",host:[$host],path:$path}},
          {type:"direct",tag:"direct"}
        ],
        route:{final:"proxy"}
      }' > "$config"
      ;;
    *) echo "Unknown transport probe: $type" >&2; return 2 ;;
  esac

  if ! sing-box check -c "$config" >/dev/null 2>&1; then
    echo "$label: config-rejected"
    return 1
  fi
  sing-box run -c "$config" >"$log" 2>&1 & pid=$!
  for _ in $(seq 1 40); do
    if has_listener "$socks_port"; then break; fi
    kill -0 "$pid" 2>/dev/null || { echo "$label: client-start-failed"; return 1; }
    sleep 0.25
  done
  has_listener "$socks_port" || { echo "$label: socks-not-ready"; return 1; }
  if curl -fsS --max-time 15 --proxy "socks5h://127.0.0.1:$socks_port" https://example.com/ >/dev/null; then
    echo "$label: pass"
    return 0
  fi
  echo "$label: data-plane-failed"
  return 1
}

ws=false
grpc=false
http2=false
probe websocket ws /aero/transport/ws 19080 && ws=true || true
probe grpc grpc wesi.aero.Transport 19081 && grpc=true || true
probe http2 http /aero/transport/h2 19082 && http2=true || true

jq -n \
  --argjson websocket "$ws" \
  --argjson grpc "$grpc" \
  --argjson http2 "$http2" \
  '{websocket:$websocket,grpc:$grpc,http2:$http2}' > "$RESULT_FILE"
chmod 600 "$RESULT_FILE"

# WebSocket/TLS/443 is the production floor. Other candidates are only promoted
# into automatic fallback after this verifier proves them independently.
if [[ "$ws" != true ]]; then
  echo "Required WebSocket/TLS/443 transport failed end-to-end verification." >&2
  exit 1
fi
cat "$RESULT_FILE"
