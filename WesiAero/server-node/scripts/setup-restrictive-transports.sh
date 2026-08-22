#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero/singbox}"
CLIENT_DIR="$STATE_DIR/clients"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/restrictive-transports.json"
SERVICE_FILE="/etc/systemd/system/wesi-aero-restrictive-transports.service"
NGINX_SNIPPET="/etc/nginx/snippets/wesi-aero-transports.conf"
UUID_FILE="$STATE_DIR/restrictive-vmess.uuid"
WS_PORT="${WESI_AERO_RESTRICTIVE_WS_PORT:-18080}"
GRPC_PORT="${WESI_AERO_RESTRICTIVE_GRPC_PORT:-18081}"
HTTP2_PORT="${WESI_AERO_RESTRICTIVE_HTTP2_PORT:-18082}"
WS_PATH="/aero/transport/ws"
HTTP2_PATH="/aero/transport/h2"
GRPC_SERVICE="wesi.aero.Transport"

[[ "$PUBLIC_HOST" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || {
  echo "A public Wesi Aero hostname is required." >&2
  exit 1
}
command -v sing-box >/dev/null 2>&1 || { echo "sing-box must be installed first." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq must be installed first." >&2; exit 1; }

install -d -m 700 "$STATE_DIR" "$CLIENT_DIR"
install -d -m 755 "$CONFIG_DIR" /etc/nginx/snippets
umask 077
if [[ ! -s "$UUID_FILE" ]]; then
  cat /proc/sys/kernel/random/uuid > "$UUID_FILE"
fi
chmod 600 "$UUID_FILE"
RESTRICTIVE_UUID="$(tr -d '[:space:]' < "$UUID_FILE")"
[[ "$RESTRICTIVE_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "Invalid restrictive VMess UUID." >&2; exit 1; }

tmp_config="$(mktemp)"
trap 'rm -f "$tmp_config"' EXIT
jq -n \
  --arg uuid "$RESTRICTIVE_UUID" \
  --arg host "$PUBLIC_HOST" \
  --arg wsPath "$WS_PATH" \
  --arg h2Path "$HTTP2_PATH" \
  --arg grpcService "$GRPC_SERVICE" \
  --argjson wsPort "$WS_PORT" \
  --argjson grpcPort "$GRPC_PORT" \
  --argjson h2Port "$HTTP2_PORT" \
  '{
    log:{level:"warn",timestamp:false},
    inbounds:[
      {
        type:"vmess",tag:"vmess-ws-443",listen:"127.0.0.1",listen_port:$wsPort,
        users:[{name:"wesi-restrictive-ws",uuid:$uuid,alterId:0}],
        transport:{type:"ws",path:$wsPath,headers:{Host:$host}}
      },
      {
        type:"vmess",tag:"vmess-grpc-443",listen:"127.0.0.1",listen_port:$grpcPort,
        users:[{name:"wesi-restrictive-grpc",uuid:$uuid,alterId:0}],
        transport:{type:"grpc",service_name:$grpcService,idle_timeout:"30s",ping_timeout:"15s"}
      },
      {
        type:"vmess",tag:"vmess-http2-443",listen:"127.0.0.1",listen_port:$h2Port,
        users:[{name:"wesi-restrictive-http2",uuid:$uuid,alterId:0}],
        transport:{type:"http",host:[$host],path:$h2Path,idle_timeout:"30s",ping_timeout:"15s"}
      }
    ],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{final:"direct"}
  }' > "$tmp_config"

# Validate before replacing the active configuration. A bad transport config
# cannot take the existing relay down.
sing-box check -c "$tmp_config"
install -m 600 "$tmp_config" "$CONFIG_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wesi Aero restrictive-network HTTPS transport gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=always
RestartSec=2
LimitNOFILE=1048576
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
# sing-box listens only on loopback TCP here, but its network manager needs
# AF_NETLINK to subscribe to route/interface changes. No packet/raw families are
# granted beyond the minimum required sockets.
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wesi-aero-restrictive-transports.service >/dev/null
# Clear an earlier start-rate limit before attempting the corrected unit. A
# subsequent crash is still fatal because readiness below checks both the unit
# and every expected listener.
systemctl reset-failed wesi-aero-restrictive-transports.service >/dev/null 2>&1 || true
if ! systemctl restart wesi-aero-restrictive-transports.service; then
  systemctl status wesi-aero-restrictive-transports.service --no-pager >&2 || true
  journalctl -u wesi-aero-restrictive-transports.service -n 40 --no-pager >&2 || true
  exit 1
fi

has_loopback_listener() {
  local port="$1"
  ss -ltnH | awk -v suffix=":$port" '
    $4 ~ suffix"$" && $4 ~ /^127\.0\.0\.1:/ { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

# systemd reports Type=simple as active immediately after exec(). sing-box still
# needs a short initialization window before its listeners exist, so service
# state alone is not a readiness signal. Wait until all three transports are
# actually bound while continuously rejecting a failed unit.
ready=false
for _ in $(seq 1 80); do
  if systemctl is-failed --quiet wesi-aero-restrictive-transports.service; then
    echo "Restrictive transport service failed before becoming ready." >&2
    systemctl status wesi-aero-restrictive-transports.service --no-pager >&2 || true
    journalctl -u wesi-aero-restrictive-transports.service -n 40 --no-pager >&2 || true
    exit 1
  fi
  if systemctl is-active --quiet wesi-aero-restrictive-transports.service && \
     has_loopback_listener "$WS_PORT" && \
     has_loopback_listener "$GRPC_PORT" && \
     has_loopback_listener "$HTTP2_PORT"; then
    ready=true
    break
  fi
  sleep 0.25
done
if [[ "$ready" != true ]]; then
  echo "Restrictive transport service did not expose all loopback listeners in time." >&2
  systemctl status wesi-aero-restrictive-transports.service --no-pager >&2 || true
  journalctl -u wesi-aero-restrictive-transports.service -n 40 --no-pager >&2 || true
  ss -ltnH >&2 || true
  exit 1
fi

# These listeners are deliberately loopback-only. Nginx is the sole public
# TLS/443 entry point; no firewall hole is created for 18080-18082. Consume the
# entire ss stream in awk so `set -o pipefail` cannot turn a successful match
# into a SIGPIPE false-negative.
for port in "$WS_PORT" "$GRPC_PORT" "$HTTP2_PORT"; do
  if ss -ltnH | awk -v suffix=":$port" '
    $4 ~ suffix"$" && $4 !~ /^127\.0\.0\.1:/ { exposed=1 }
    END { exit(exposed ? 0 : 1) }
  '; then
    echo "Restrictive transport port $port is exposed outside loopback." >&2
    exit 1
  fi
done

cat > "$NGINX_SNIPPET" <<'NGINX'
# Wesi Aero standards-compliant restrictive-network transports.
# TLS terminates on the Wesi-owned hostname. No third-party SNI/domain fronting.
location = /aero/transport/ws {
    proxy_pass http://127.0.0.1:18080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Real-IP "";
    proxy_set_header X-Forwarded-For "";
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}

location ^~ /wesi.aero.Transport/ {
    grpc_pass grpc://127.0.0.1:18081;
    grpc_set_header Host $host;
    grpc_set_header X-Real-IP "";
    grpc_set_header X-Forwarded-For "";
    grpc_read_timeout 3600s;
    grpc_send_timeout 3600s;
}

location ^~ /aero/transport/h2 {
    proxy_pass http://127.0.0.1:18082;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP "";
    proxy_set_header X-Forwarded-For "";
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
NGINX
chmod 644 "$NGINX_SNIPPET"

write_vmess_profile() {
  local target="$1" name="$2" network="$3" path="$4"
  local payload
  payload="$(jq -cn \
    --arg name "$name" \
    --arg host "$PUBLIC_HOST" \
    --arg uuid "$RESTRICTIVE_UUID" \
    --arg network "$network" \
    --arg path "$path" \
    '{v:"2",ps:$name,add:$host,port:"443",id:$uuid,aid:"0",scy:"auto",net:$network,type:"none",host:$host,path:$path,tls:"tls",sni:$host,fp:"chrome"}')"
  printf 'vmess://%s\n' "$(printf '%s' "$payload" | base64 -w0)" > "$target"
  chmod 600 "$target"
}

# WS is the first live restrictive profile because the current Android sing-box
# backend already validates and consumes VMess+WS+TLS. gRPC is also supported by
# the current client. HTTP/2 is provisioned server-side and kept as a separate
# candidate until its client parser is promoted to the same tested status.
write_vmess_profile "$CLIENT_DIR/vmess-ws443.txt" "Wesi Relay HTTPS WS" "ws" "$WS_PATH"
write_vmess_profile "$CLIENT_DIR/vmess-grpc443.txt" "Wesi Relay HTTPS gRPC" "grpc" "$GRPC_SERVICE"
write_vmess_profile "$CLIENT_DIR/vmess-http2-443.txt" "Wesi Relay HTTPS HTTP2" "http" "$HTTP2_PATH"

for profile in "$CLIENT_DIR"/vmess-ws443.txt "$CLIENT_DIR"/vmess-grpc443.txt "$CLIENT_DIR"/vmess-http2-443.txt; do
  decoded="$(sed 's#^vmess://##' "$profile" | base64 -d)"
  jq -e --arg host "$PUBLIC_HOST" '.add==$host and .port=="443" and .sni==$host and .tls=="tls"' <<<"$decoded" >/dev/null
done

echo "Wesi Aero restrictive transports ready on the Wesi-owned TLS/443 facade: WebSocket, gRPC and HTTP/2."
