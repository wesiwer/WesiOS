#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-wesi-inc.ru}"
WWW_DOMAIN="${WWW_DOMAIN:-www.wesi-inc.ru}"
BRANCH="${BRANCH:-chatgpt/gpt-5.6-work}"
REPO_RAW="https://raw.githubusercontent.com/wesiwer/WesiOS/${BRANCH}"
RELEASE_BASE="https://github.com/wesiwer/WesiOS/releases/download/app-latest"
WEB_ROOT="/var/www/wesios-portal"
APP_ROOT="/opt/wesios-portal"
RELEASE_DIR="/srv/wesios-releases"
NGINX_SITE="/etc/nginx/sites-available/wesi-inc.ru"
ENV_FILE="/etc/wesios-portal.env"
SERVICE_FILE="/etc/systemd/system/wesios-portal.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root." >&2
  exit 1
fi

apt-get update -qq
apt-get install -y -qq curl nginx certbot python3-certbot-nginx python3-venv

mkdir -p "$WEB_ROOT" "$APP_ROOT" "$RELEASE_DIR"
for file in index.html styles.css app.js; do
  echo "Загружаю website/$file"
  curl -fL "$REPO_RAW/website/$file" -o "$WEB_ROOT/$file"
done
curl -fL "$REPO_RAW/server/employee_portal_gateway.py" -o "$APP_ROOT/gateway.py"

python3 -m venv "$APP_ROOT/venv"
"$APP_ROOT/venv/bin/pip" install --disable-pip-version-check -q --upgrade pip
"$APP_ROOT/venv/bin/pip" install --disable-pip-version-check -q flask requests gunicorn

if [[ ! -f "$ENV_FILE" ]]; then
  SECRET="$(openssl rand -hex 48)"
  cat > "$ENV_FILE" <<EOF
PB_URL=http://127.0.0.1:8090
RELEASE_DIR=$RELEASE_DIR
PORTAL_SESSION_SECRET=$SECRET
PORTAL_SESSION_TTL=28800
EOF
  chmod 600 "$ENV_FILE"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WesiOS Employee Portal Gateway
After=network-online.target pocketbase.service
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
EnvironmentFile=$ENV_FILE
WorkingDirectory=$APP_ROOT
ExecStart=$APP_ROOT/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8091 --access-logfile - --error-logfile - gateway:app
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=$RELEASE_DIR

[Install]
WantedBy=multi-user.target
EOF

# Временная первичная загрузка актуальных файлов. После настройки CI файлы
# должны попадать сюда напрямую, а публичные GitHub-ассеты следует отключить.
for file in app-manifest.json wesios-windows-x64.zip wesios-android.apk; do
  if curl -fL --retry 2 "$RELEASE_BASE/$file" -o "$RELEASE_DIR/$file.tmp"; then
    mv "$RELEASE_DIR/$file.tmp" "$RELEASE_DIR/$file"
  else
    rm -f "$RELEASE_DIR/$file.tmp"
    echo "Предупреждение: $file пока отсутствует в app-latest."
  fi
done

chown -R www-data:www-data "$WEB_ROOT" "$APP_ROOT" "$RELEASE_DIR"
find "$WEB_ROOT" -type d -exec chmod 755 {} +
find "$WEB_ROOT" -type f -exec chmod 644 {} +
find "$RELEASE_DIR" -type f -exec chmod 640 {} +

systemctl daemon-reload
systemctl enable --now wesios-portal

cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} ${WWW_DOMAIN};

    root ${WEB_ROOT};
    index index.html;
    client_max_body_size 2m;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /portal/ {
        proxy_pass http://127.0.0.1:8091/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_buffering off;
    }

    location ~* \.(css|js)$ {
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
        try_files \$uri =404;
    }

    add_header Content-Security-Policy "default-src 'self'; connect-src 'self' https://api.wesi-inc.ru; style-src 'self' 'unsafe-inline'; script-src 'self'; img-src 'self' data: blob:; font-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Frame-Options DENY always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
}
EOF

ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/wesi-inc.ru
nginx -t
systemctl reload nginx

SERVER_IP="$(curl -fsS -4 https://api.ipify.org || true)"
DOMAIN_IP="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}' || true)"
WWW_IP="$(getent ahostsv4 "$WWW_DOMAIN" 2>/dev/null | awk 'NR==1{print $1}' || true)"

echo
echo "Портал и защищённый шлюз установлены."
echo "Gateway: $(systemctl is-active wesios-portal || true)"
echo "IP сервера: ${SERVER_IP:-не определён}"
echo "${DOMAIN} -> ${DOMAIN_IP:-DNS ещё не настроен}"
echo "${WWW_DOMAIN} -> ${WWW_IP:-DNS ещё не настроен}"

if [[ -n "$SERVER_IP" && "$DOMAIN_IP" == "$SERVER_IP" ]]; then
  CERT_DOMAINS=(-d "$DOMAIN")
  if [[ "$WWW_IP" == "$SERVER_IP" ]]; then CERT_DOMAINS+=(-d "$WWW_DOMAIN"); fi
  certbot --nginx --non-interactive --agree-tos \
    --email "wesiofficial01@gmail.com" --redirect "${CERT_DOMAINS[@]}"
  echo "Готово: https://${DOMAIN}"
else
  echo "HTTPS пока не выпускался: направь DNS A-запись @ на ${SERVER_IP:-IP сервера}."
  echo "Для www добавь CNAME www -> ${DOMAIN}. Затем повторно запусти скрипт."
fi

echo
echo "Проверки:"
echo "  curl http://127.0.0.1:8091/health"
echo "  systemctl status wesios-portal --no-pager"
echo "  nginx -t"
