#!/usr/bin/env bash
# Configure the public HTTPS facade for Wesi AI Relay on Debian/Ubuntu.
set -euo pipefail

HOSTNAME="${1:-}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE=/etc/nginx/sites-available/wesi-ai-relay
ENABLED=/etc/nginx/sites-enabled/wesi-ai-relay
ACME_ROOT=/var/www/wesi-ai-relay-acme

fail() { echo "[wesi-ai-https] ERROR: $*" >&2; exit 2; }
log() { echo "[wesi-ai-https] $*"; }

[ "$(id -u)" -eq 0 ] || fail "Запустите скрипт через sudo/root."
[[ "$HOSTNAME" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || fail "Нужен DNS hostname, например relay.example.com (не IP и не URL)."

log "checking local Relay health"
command -v curl >/dev/null 2>&1 || fail "curl не установлен."
curl -fsS --max-time 10 http://127.0.0.1:8787/health | grep -q '"ok":true' || fail "Relay не отвечает на 127.0.0.1:8787/health."

if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1; then
  log "installing nginx and certbot"
  command -v apt-get >/dev/null 2>&1 || fail "Автоустановка поддерживает Debian/Ubuntu."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nginx certbot
fi

log "configuring HTTP ACME endpoint"
mkdir -p "$ACME_ROOT/.well-known/acme-challenge"
chmod 755 "$ACME_ROOT" "$ACME_ROOT/.well-known" "$ACME_ROOT/.well-known/acme-challenge"
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
  log "requesting Let's Encrypt certificate for $HOSTNAME"
  certbot certonly --webroot -w "$ACME_ROOT" -d "$HOSTNAME" --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring || {
    log "certbot failed; showing DNS and listeners"
    getent ahostsv4 "$HOSTNAME" || true
    ss -ltnp | grep -E ':(80|443|8787)\b' || true
    journalctl -u nginx -n 60 --no-pager || true
    fail "Let's Encrypt validation failed. Проверьте DNS и входящие TCP 80/443."
  }
fi

[ -s "$CERT_DIR/fullchain.pem" ] || fail "Let's Encrypt certificate was not created."
[ -s "$CERT_DIR/privkey.pem" ] || fail "Let's Encrypt private key was not created."

log "installing HTTPS reverse proxy"
test -s "$SOURCE_DIR/nginx-relay.conf" || fail "nginx-relay.conf is missing next to this script."
sed "s/RELAY_HOST_PLACEHOLDER/$HOSTNAME/g" "$SOURCE_DIR/nginx-relay.conf" > "$SITE"
ln -sfn "$SITE" "$ENABLED"
nginx -t
systemctl reload nginx
if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then systemctl enable --now certbot.timer >/dev/null 2>&1 || true; fi

log "verifying public HTTPS health"
curl -fsS --max-time 20 "https://$HOSTNAME/health" | grep -q '"ok":true' || fail "Public /health verification failed."
for route in /v1/wesi-ai /v1/wesi-ai-artifact; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -X POST "https://$HOSTNAME$route" || true)"
  [ "$code" = "401" ] || fail "Expected 401 from unsigned $route request, got HTTP $code."
done
log "Relay HTTPS ready: https://$HOSTNAME"
