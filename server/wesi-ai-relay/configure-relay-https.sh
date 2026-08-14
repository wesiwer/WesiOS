#!/usr/bin/env bash
# Configure the public HTTPS facade for Wesi AI Relay on Debian/Ubuntu.
#
# Preconditions owned by infrastructure/DNS, not by this script:
#   - RELAY_HOSTNAME resolves to this server's public IP;
#   - inbound TCP 80 and 443 are allowed by the VPS/cloud firewall;
#   - Relay already answers on 127.0.0.1:8787.
#
# Usage (root):
#   bash configure-relay-https.sh relay.example.com
#
# Safe to run again for updates/renewal configuration.

set -euo pipefail

HOSTNAME="${1:-}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE=/etc/nginx/sites-available/wesi-ai-relay
ENABLED=/etc/nginx/sites-enabled/wesi-ai-relay
ACME_ROOT=/var/www/wesi-ai-relay-acme

fail() {
  echo "$*" >&2
  exit 2
}

[ "$(id -u)" -eq 0 ] || fail "Запустите скрипт через sudo/root."
[[ "$HOSTNAME" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] \
  || fail "Нужен DNS hostname, например relay.example.com (не IP и не URL)."

command -v curl >/dev/null 2>&1 || fail "curl не установлен."
curl -fsS --max-time 10 http://127.0.0.1:8787/health | grep -q '"ok":true' \
  || fail "Relay не отвечает на 127.0.0.1:8787/health. Сначала установите Relay."

if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 \
    || fail "Автоустановка поддерживает Debian/Ubuntu. Установите nginx+certbot вручную."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nginx certbot
fi

mkdir -p "$ACME_ROOT/.well-known/acme-challenge"
chmod 755 "$ACME_ROOT" "$ACME_ROOT/.well-known" "$ACME_ROOT/.well-known/acme-challenge"

# Bootstrap HTTP-only site so Let's Encrypt can validate without exposing the
# Relay endpoint over plaintext HTTP.
cat > "$SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / { return 404; }
}
NGINX
ln -sfn "$SITE" "$ENABLED"
nginx -t
systemctl enable --now nginx
systemctl reload nginx

CERT_DIR="/etc/letsencrypt/live/$HOSTNAME"
if [ ! -s "$CERT_DIR/fullchain.pem" ] || [ ! -s "$CERT_DIR/privkey.pem" ]; then
  certbot certonly \
    --webroot -w "$ACME_ROOT" \
    -d "$HOSTNAME" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --keep-until-expiring
fi

[ -s "$CERT_DIR/fullchain.pem" ] || fail "Let's Encrypt certificate was not created. Check DNS and port 80."
[ -s "$CERT_DIR/privkey.pem" ] || fail "Let's Encrypt private key was not created."

test -s "$SOURCE_DIR/nginx-relay.conf" || fail "nginx-relay.conf is missing next to this script."
sed "s/RELAY_HOST_PLACEHOLDER/$HOSTNAME/g" "$SOURCE_DIR/nginx-relay.conf" > "$SITE"
ln -sfn "$SITE" "$ENABLED"
nginx -t
systemctl reload nginx

if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true
fi

curl -fsS --max-time 20 "https://$HOSTNAME/health" | grep -q '"ok":true' \
  || fail "HTTPS configured, but public /health verification failed. Check DNS/firewall/nginx logs."

# Both write surfaces are internet-reachable through nginx but are usable only
# by Main Server. An unsigned request must reach Relay and be rejected as 401;
# 404 would indicate a broken proxy and 2xx would indicate an auth failure.
for route in /v1/wesi-ai /v1/wesi-ai-artifact; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$HOSTNAME$route" || true)"
  [ "$code" = "401" ] || fail "Expected 401 from unsigned $route request, got HTTP $code."
done

echo "Relay HTTPS ready: https://$HOSTNAME"
