#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero/singbox}"
CLIENT_DIR="$STATE_DIR/clients"
SECRETS_FILE="$STATE_DIR/secrets.env"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/restrictive-transports.json"
SERVICE_FILE="/etc/systemd/system/wesi-aero-restrictive-transports.service"
NGINX_SNIPPET="/etc/nginx/snippets/wesi-aero-transports.conf"
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
[[ -s "$SECRETS_FILE" ]] || { echo "sing-box secrets are missing." >&2; exit 1; }
# shellcheck disable=SC1090
source "$SECRETS_FILE"
: "${TROJAN_PASSWORD:?TROJAN_PASSWORD is missing}"

install -d -m 700 "$STATE_DIR" "$CLIENT_DIR"
install -d -m 755 "$CONFIG_DIR" /etc/nginx/snippets

tmp_config="$(mktemp)"
trap 'rm -f "$tmp_config"' EXIT
jq -n \
  --arg password "$TROJAN_PASSWORD" \
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
        type:"trojan",tag:"trojan-ws-443",listen:"127.0.0.1",listen_port:$wsPort,
        users:[{name:"wesi-restrictive-ws",password:$password}],
        transport:{type:"ws",path:$wsPath,headers:{Host:$host}}
      },
      {
        type:"trojan",tag:"trojan-grpc-443",listen:"127.0.0.1",listen_port:$grpcPort,
        users:[{name:"wesi-restrictive-grpc",password:$password}],
        transport:{type:"grpc",service_name:$grpcService,idle_timeout:"30s",ping_timeout:"15s"}
      },
      {
        type:"trojan",tag:"trojan-http2-443",listen:"127.0.0.1",listen_port:$h2Port,
        users:[{name:"wesi-restrictive-http2",password:$password}],
        transport:{type:"http",host:[$host],path:$h2Path,idle_timeout:"30s",ping_timeout:"15s"}
      }
    ],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{final:"direct"}
  }' > "$tmp_config"

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
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadOnlyPaths=/etc/letsencrypt

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wesi-aero-restrictive-transports.service >/dev/null
systemctl restart wesi-aero-restrictive-transports.service
for _ in $(seq 1 40); do
  systemctl is-active --quiet wesi-aero-restrictive-transports.service && break
  sleep 0.25
done
systemctl is-active --quiet wesi-aero-restrictive-transports.service

# These listeners are deliberately loopback-only. Nginx is the sole public
# TLS/443 entry point; no firewall hole is created for 18080-18082.
for port in "$WS_PORT" "$GRPC_PORT" "$HTTP2_PORT"; do
  ss -ltn | grep -Eq "127\\.0\\.0\\.1:${port}[[:space:]]"
  if ss -ltn | grep -Eq "(0\\.0\\.0\\.0|\\[::\\]|:::):?${port}[[:space:]]"; then
    echo "Restrictive transport port $port is exposed publicly." >&2
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

urlencode() {
  jq -nr --arg value "$1" '$value|@uri'
}
ws_path_q="$(urlencode "$WS_PATH")"
h2_path_q="$(urlencode "$HTTP2_PATH")"
grpc_q="$(urlencode "$GRPC_SERVICE")"
printf 'trojan://%s@%s:443?security=tls&sni=%s&type=ws&host=%s&path=%s#Wesi%%20Relay%%20HTTPS%%20WS\n' \
  "$TROJAN_PASSWORD" "$PUBLIC_HOST" "$PUBLIC_HOST" "$PUBLIC_HOST" "$ws_path_q" > "$CLIENT_DIR/trojan-ws443.txt"
printf 'trojan://%s@%s:443?security=tls&sni=%s&type=grpc&serviceName=%s#Wesi%%20Relay%%20HTTPS%%20gRPC\n' \
  "$TROJAN_PASSWORD" "$PUBLIC_HOST" "$PUBLIC_HOST" "$grpc_q" > "$CLIENT_DIR/trojan-grpc443.txt"
printf 'trojan://%s@%s:443?security=tls&sni=%s&type=http&host=%s&path=%s#Wesi%%20Relay%%20HTTPS%%20HTTP2\n' \
  "$TROJAN_PASSWORD" "$PUBLIC_HOST" "$PUBLIC_HOST" "$PUBLIC_HOST" "$h2_path_q" > "$CLIENT_DIR/trojan-http2-443.txt"
chmod 600 "$CLIENT_DIR"/trojan-ws443.txt "$CLIENT_DIR"/trojan-grpc443.txt "$CLIENT_DIR"/trojan-http2-443.txt

for profile in "$CLIENT_DIR"/trojan-ws443.txt "$CLIENT_DIR"/trojan-grpc443.txt "$CLIENT_DIR"/trojan-http2-443.txt; do
  grep -Fq "@${PUBLIC_HOST}:443?" "$profile"
  grep -Fq "sni=${PUBLIC_HOST}" "$profile"
done

echo "Wesi Aero restrictive transports ready on the Wesi-owned TLS/443 facade: WebSocket, gRPC and HTTP/2."
