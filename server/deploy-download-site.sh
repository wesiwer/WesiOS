#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-wesi-inc.ru}"
WWW_DOMAIN="${WWW_DOMAIN:-www.wesi-inc.ru}"
BRANCH="${BRANCH:-chatgpt/gpt-5.6-work}"
REPO_RAW="https://raw.githubusercontent.com/wesiwer/WesiOS/${BRANCH}"
WEB_ROOT="/var/www/wesios-download"
NGINX_SITE="/etc/nginx/sites-available/wesi-inc.ru"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root." >&2
  exit 1
fi

command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }
command -v nginx >/dev/null || { apt-get update && apt-get install -y nginx; }
command -v certbot >/dev/null || { apt-get update && apt-get install -y certbot python3-certbot-nginx; }

mkdir -p "$WEB_ROOT"
for file in index.html styles.css app.js; do
  echo "Загружаю website/$file"
  curl -fL "$REPO_RAW/website/$file" -o "$WEB_ROOT/$file"
done
chown -R www-data:www-data "$WEB_ROOT"
find "$WEB_ROOT" -type d -exec chmod 755 {} +
find "$WEB_ROOT" -type f -exec chmod 644 {} +

cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} ${WWW_DOMAIN};

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location = /app-manifest.json {
        return 302 https://github.com/wesiwer/WesiOS/releases/download/app-latest/app-manifest.json;
    }

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options DENY always;

    location ~* \.(css|js)$ {
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
        try_files \$uri =404;
    }
}
EOF

ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/wesi-inc.ru
nginx -t
systemctl reload nginx

SERVER_IP="$(curl -fsS -4 https://api.ipify.org || true)"
DOMAIN_IP="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}' || true)"
WWW_IP="$(getent ahostsv4 "$WWW_DOMAIN" 2>/dev/null | awk 'NR==1{print $1}' || true)"

echo
echo "Сайт по HTTP настроен."
echo "IP сервера: ${SERVER_IP:-не определён}"
echo "${DOMAIN} -> ${DOMAIN_IP:-DNS ещё не настроен}"
echo "${WWW_DOMAIN} -> ${WWW_IP:-DNS ещё не настроен}"

if [[ -n "$SERVER_IP" && "$DOMAIN_IP" == "$SERVER_IP" ]]; then
  CERT_DOMAINS=(-d "$DOMAIN")
  if [[ "$WWW_IP" == "$SERVER_IP" ]]; then
    CERT_DOMAINS+=(-d "$WWW_DOMAIN")
  fi
  echo "DNS уже указывает на сервер — выпускаю HTTPS."
  certbot --nginx --non-interactive --agree-tos \
    --email "wesiofficial01@gmail.com" \
    --redirect "${CERT_DOMAINS[@]}"
  echo "Готово: https://${DOMAIN}"
else
  echo
  echo "HTTPS пока не выпускался: сначала направь DNS A-запись @ на ${SERVER_IP:-IP сервера}."
  echo "Для www добавь CNAME www -> ${DOMAIN} либо A-запись на тот же IP."
  echo "После распространения DNS повторно запусти этот же скрипт."
fi
