#!/usr/bin/env bash
# Завершает настройку уже работающего PocketBase для WesiOS.
# Не переустанавливает ОС и PocketBase, не удаляет pb_data.
set -Eeuo pipefail

PB_DIR=/opt/pocketbase
PB_BIN="$PB_DIR/pocketbase"
PB_DATA="$PB_DIR/pb_data"
PB_PUBLIC="$PB_DIR/pb_public"
HOST=http://127.0.0.1:8090
REPO_RAW=https://raw.githubusercontent.com/wesiwer/WesiOS/chatgpt/gpt-5.6-work/server

say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || die "Запустите от root"
[[ -x "$PB_BIN" ]] || die "PocketBase не найден: $PB_BIN"
curl -fsS "$HOST/api/health" >/dev/null || die "PocketBase не отвечает на $HOST"

read -r -p 'Email суперпользователя PocketBase: ' ADMIN_EMAIL
read -r -s -p 'Пароль суперпользователя PocketBase: ' ADMIN_PASS; echo
read -r -p 'Email отдельного пользователя для приложения WesiOS: ' APP_EMAIL
read -r -s -p 'Пароль пользователя приложения WesiOS: ' APP_PASS; echo
[[ "$ADMIN_EMAIL" == *'@'* && "$APP_EMAIL" == *'@'* ]] || die "Некорректный email"
[[ ${#ADMIN_PASS} -ge 8 && ${#APP_PASS} -ge 10 ]] || die "Пароль приложения должен быть не короче 10 символов"

say 'Устанавливаю системные зависимости'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq sqlite3 ufw fail2ban

say 'Создаю коллекции и пользователя приложения'
curl -fsSL "$REPO_RAW/setup-collections.sh" -o /root/wesios-setup-collections.sh
chmod 700 /root/wesios-setup-collections.sh
/root/wesios-setup-collections.sh \
  --admin "$ADMIN_EMAIL" --admin-pass "$ADMIN_PASS" \
  --user "$APP_EMAIL" --user-pass "$APP_PASS"
rm -f /root/wesios-setup-collections.sh

say 'Устанавливаю агент мониторинга'
install -d -m 0755 "$PB_PUBLIC"
curl -fsSL "$REPO_RAW/wesios-agent.sh" -o /root/wesios-agent.sh
chmod 700 /root/wesios-agent.sh
bash /root/wesios-agent.sh --install

say 'Настраиваю безопасные SQLite-бэкапы'
install -d -m 0750 "$PB_DIR/backups"
cat >/usr/local/sbin/wesios-pocketbase-backup <<'BACKUP'
#!/usr/bin/env bash
set -Eeuo pipefail
DB=/opt/pocketbase/pb_data/data.db
DIR=/opt/pocketbase/backups
[[ -f "$DB" ]] || exit 0
mkdir -p "$DIR"
OUT="$DIR/data-$(date -u +%F_%H-%M-%S).db"
sqlite3 "$DB" ".timeout 10000" ".backup '$OUT'"
chmod 600 "$OUT"
find "$DIR" -type f -name 'data-*.db' -mtime +14 -delete
BACKUP
chmod 700 /usr/local/sbin/wesios-pocketbase-backup
cat >/etc/systemd/system/wesios-backup.service <<'EOF'
[Unit]
Description=WesiOS PocketBase backup
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wesios-pocketbase-backup
EOF
cat >/etc/systemd/system/wesios-backup.timer <<'EOF'
[Unit]
Description=Daily WesiOS PocketBase backup
[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=15m
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now wesios-backup.timer
systemctl start wesios-backup.service

say 'Настраиваю fail2ban и UFW'
cat >/etc/fail2ban/jail.d/wesios.conf <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban
ufw allow OpenSSH >/dev/null
ufw allow 8090/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

say 'Финальная проверка'
systemctl is-active --quiet pocketbase || die 'PocketBase не активен'
systemctl is-active --quiet ssh || die 'SSH не активен'
systemctl is-active --quiet fail2ban || die 'fail2ban не активен'
systemctl is-active --quiet wesios-backup.timer || die 'таймер бэкапов не активен'
curl -fsS "$HOST/api/health" | jq .
[[ -f "$PB_PUBLIC/wesios-status.json" ]] || echo 'WARN: агент ещё не создал wesios-status.json; подождите минуту'

PUBLIC_IP=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
printf '\nГОТОВО\nПанель: http://%s:8090/_/\nАдрес WesiOS: %s:8090\nАгент: http://%s:8090/wesios-status.json\nБэкапы: /opt/pocketbase/backups\n' "$PUBLIC_IP" "$PUBLIC_IP" "$PUBLIC_IP"
printf '\nВажно: это временный HTTP. Следующий этап — домен и HTTPS.\n'
unset ADMIN_PASS APP_PASS
