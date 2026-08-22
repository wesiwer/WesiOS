#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

VERSION="${WESI_AERO_SINGBOX_VERSION:-1.13.18}"
PUBLIC_HOST="${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}"
TROJAN_PORT="${WESI_AERO_TROJAN_PORT:-8445}"
SS_PORT="${WESI_AERO_SHADOWSOCKS_PORT:-8388}"
HY2_PORT="${WESI_AERO_HYSTERIA2_PORT:-8446}"
TUIC_PORT="${WESI_AERO_TUIC_PORT:-8447}"
STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero/singbox}"
CLIENT_DIR="$STATE_DIR/clients"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
SECRETS_FILE="$STATE_DIR/secrets.env"
SERVICE_FILE="/etc/systemd/system/wesi-aero-singbox.service"
CERT_DIR="/etc/letsencrypt/live/$PUBLIC_HOST"

[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || {
  echo "TLS certificate for $PUBLIC_HOST is required before sing-box setup." >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y curl ca-certificates jq openssl tar >/dev/null

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) asset_arch=amd64 ;;
  aarch64|arm64) asset_arch=arm64 ;;
  *) echo "Unsupported sing-box server architecture: $arch" >&2; exit 1 ;;
esac

install -d -m 700 "$STATE_DIR" "$CLIENT_DIR"
install -d -m 755 "$CONFIG_DIR"

if [[ ! -s "$SECRETS_FILE" ]]; then
  umask 077
  TROJAN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=/+' | head -c 32)"
  SS_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"
  HY2_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=/+' | head -c 32)"
  TUIC_UUID="$(cat /proc/sys/kernel/random/uuid)"
  TUIC_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=/+' | head -c 32)"
  cat > "$SECRETS_FILE" <<EOF
TROJAN_PASSWORD=$TROJAN_PASSWORD
SS_PASSWORD=$SS_PASSWORD
HY2_PASSWORD=$HY2_PASSWORD
TUIC_UUID=$TUIC_UUID
TUIC_PASSWORD=$TUIC_PASSWORD
EOF
fi
chmod 600 "$SECRETS_FILE"
# shellcheck disable=SC1090
source "$SECRETS_FILE"

need_install=true
if command -v sing-box >/dev/null 2>&1; then
  current="$(sing-box version 2>/dev/null | awk '/sing-box version/{print $3; exit}')"
  [[ "$current" == "$VERSION" ]] && need_install=false
fi
if [[ "$need_install" == true ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  base="sing-box-${VERSION}-linux-${asset_arch}"
  curl -fsSL --retry 3 \
    "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${base}.tar.gz" \
    -o "$tmp/sing-box.tar.gz"
  tar -xzf "$tmp/sing-box.tar.gz" -C "$tmp"
  install -m 755 "$tmp/$base/sing-box" /usr/local/bin/sing-box
fi
sing-box version | grep -q "sing-box version $VERSION"

jq -n \
  --arg host "$PUBLIC_HOST" \
  --arg cert "$CERT_DIR/fullchain.pem" \
  --arg key "$CERT_DIR/privkey.pem" \
  --arg trojan "$TROJAN_PASSWORD" \
  --arg ss "$SS_PASSWORD" \
  --arg hy2 "$HY2_PASSWORD" \
  --arg tuicUuid "$TUIC_UUID" \
  --arg tuicPassword "$TUIC_PASSWORD" \
  --argjson trojanPort "$TROJAN_PORT" \
  --argjson ssPort "$SS_PORT" \
  --argjson hy2Port "$HY2_PORT" \
  --argjson tuicPort "$TUIC_PORT" \
  '{
    log: {level:"warn", timestamp:true},
    inbounds: [
      {
        type:"trojan", tag:"trojan-in", listen:"::", listen_port:$trojanPort,
        users:[{name:"wesi",password:$trojan}],
        tls:{enabled:true,server_name:$host,certificate_path:$cert,key_path:$key}
      },
      {
        type:"shadowsocks", tag:"ss-in", listen:"::", listen_port:$ssPort,
        network:"tcp", method:"2022-blake3-aes-128-gcm", password:$ss,
        multiplex:{enabled:true}
      },
      {
        type:"hysteria2", tag:"hy2-in", listen:"::", listen_port:$hy2Port,
        users:[{name:"wesi",password:$hy2}], ignore_client_bandwidth:true,
        tls:{enabled:true,server_name:$host,alpn:["h3"],certificate_path:$cert,key_path:$key}
      },
      {
        type:"tuic", tag:"tuic-in", listen:"::", listen_port:$tuicPort,
        users:[{name:"wesi",uuid:$tuicUuid,password:$tuicPassword}],
        congestion_control:"bbr", zero_rtt_handshake:false,
        tls:{enabled:true,server_name:$host,alpn:["h3"],certificate_path:$cert,key_path:$key}
      }
    ],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{final:"direct"}
  }' > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
sing-box check -c "$CONFIG_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wesi Aero sing-box relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=read-only
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now wesi-aero-singbox.service >/dev/null
systemctl restart wesi-aero-singbox.service

# Host firewall rules are idempotent. QUIC transports use UDP.
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$TROJAN_PORT/tcp" >/dev/null 2>&1 || true
  ufw allow "$SS_PORT/tcp" >/dev/null 2>&1 || true
  ufw allow "$HY2_PORT/udp" >/dev/null 2>&1 || true
  ufw allow "$TUIC_PORT/udp" >/dev/null 2>&1 || true
fi
iptables -C INPUT -p tcp --dport "$TROJAN_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$TROJAN_PORT" -j ACCEPT
iptables -C INPUT -p tcp --dport "$SS_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$SS_PORT" -j ACCEPT
iptables -C INPUT -p udp --dport "$HY2_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$HY2_PORT" -j ACCEPT
iptables -C INPUT -p udp --dport "$TUIC_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$TUIC_PORT" -j ACCEPT

# Client profiles consumed by the control-plane static provisioner.
printf 'trojan://%s@%s:%s?security=tls&sni=%s#Wesi%%20Relay%%20Trojan\n' \
  "$TROJAN_PASSWORD" "$PUBLIC_HOST" "$TROJAN_PORT" "$PUBLIC_HOST" > "$CLIENT_DIR/trojan.txt"
ss_auth="$(printf '2022-blake3-aes-128-gcm:%s' "$SS_PASSWORD" | base64 -w0)"
printf 'ss://%s@%s:%s#Wesi%%20Relay%%20Shadowsocks\n' "$ss_auth" "$PUBLIC_HOST" "$SS_PORT" > "$CLIENT_DIR/shadowsocks.txt"
printf 'hysteria2://%s@%s:%s?sni=%s#Wesi%%20Relay%%20Hysteria2\n' \
  "$HY2_PASSWORD" "$PUBLIC_HOST" "$HY2_PORT" "$PUBLIC_HOST" > "$CLIENT_DIR/hysteria2.txt"
printf 'tuic://%s:%s@%s:%s?sni=%s&alpn=h3&congestion_control=bbr#Wesi%%20Relay%%20TUIC\n' \
  "$TUIC_UUID" "$TUIC_PASSWORD" "$PUBLIC_HOST" "$TUIC_PORT" "$PUBLIC_HOST" > "$CLIENT_DIR/tuic.txt"
chmod 600 "$CLIENT_DIR"/*.txt

for _ in $(seq 1 30); do
  if systemctl is-active --quiet wesi-aero-singbox.service; then break; fi
  sleep 0.25
done
systemctl is-active --quiet wesi-aero-singbox.service
ss -ltn | grep -q ":$TROJAN_PORT "
ss -ltn | grep -q ":$SS_PORT "
ss -lun | grep -q ":$HY2_PORT "
ss -lun | grep -q ":$TUIC_PORT "

echo "Wesi Aero sing-box relay active: Trojan:$TROJAN_PORT Shadowsocks:$SS_PORT Hysteria2:$HY2_PORT/udp TUIC:$TUIC_PORT/udp"
