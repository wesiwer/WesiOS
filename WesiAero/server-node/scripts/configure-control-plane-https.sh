#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

HOSTNAME="${1:-${WESI_AERO_PUBLIC_HOST:-wesi-aero-178-236-247-194.nip.io}}"
SITE="/etc/nginx/sites-available/wesi-aero-control"
ENABLED="/etc/nginx/sites-enabled/wesi-aero-control"
ACME_ROOT="/var/www/wesi-aero-acme"
TRANSPORT_SNIPPET="/etc/nginx/snippets/wesi-aero-transports.conf"

[[ "$HOSTNAME" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] || {
  echo "A public DNS hostname is required." >&2
  exit 1
}

curl -fsS --max-time 5 http://127.0.0.1:8790/healthz >/dev/null

if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y nginx certbot
fi

install -d -m 755 "$ACME_ROOT/.well-known/acme-challenge" /etc/nginx/snippets
# The HTTPS facade remains deployable before the optional restrictive transport
# service. setup-restrictive-transports.sh replaces this empty file atomically.
if [[ ! -e "$TRANSPORT_SNIPPET" ]]; then
  install -m 644 /dev/null "$TRANSPORT_SNIPPET"
fi

cat > "$SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;

    # A privacy VPN control plane should not retain source IP + request path
    # metadata merely because the reverse proxy defaults to access logging.
    access_log off;
    server_tokens off;

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
systemctl enable --now nginx >/dev/null
systemctl reload nginx

CERT_DIR="/etc/letsencrypt/live/$HOSTNAME"
if [[ ! -s "$CERT_DIR/fullchain.pem" || ! -s "$CERT_DIR/privkey.pem" ]]; then
  certbot certonly \
    --webroot -w "$ACME_ROOT" \
    -d "$HOSTNAME" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --keep-until-expiring
fi

[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || {
  echo "TLS certificate was not created." >&2
  exit 1
}

cat > "$SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;
    access_log off;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type text/plain;
        try_files \$uri =404;
    }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $HOSTNAME;

    # Do not persist per-client request metadata. Operational health should be
    # measured with aggregate/service metrics rather than identifiable access
    # logs. Critical nginx errors remain available through the normal error log.
    access_log off;
    server_tokens off;

    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:WesiAeroSSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;

    client_max_body_size 256k;

    # Optional long-lived VPN transports share the same standards-compliant
    # TLS/443 Wesi Aero endpoint. They are loopback-only behind this vhost and
    # never use third-party SNI/domain-fronting.
    include $TRANSPORT_SNIPPET;

    location / {
        proxy_pass http://127.0.0.1:8790;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        # The Node control plane does not require the user's source address.
        # Deliberately do not forward X-Real-IP/X-Forwarded-For.
        proxy_set_header X-Real-IP "";
        proxy_set_header X-Forwarded-For "";
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
NGINX

ln -sfn "$SITE" "$ENABLED"
nginx -t
systemctl reload nginx
if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true
fi

curl -fsS --max-time 20 "https://$HOSTNAME/healthz" | grep -q '"status":"ok"'
curl -fsS --max-time 20 "https://$HOSTNAME/v1/catalog" | jq -e '.servers | length >= 1' >/dev/null

echo "Wesi Aero HTTPS facade is active at https://$HOSTNAME"
