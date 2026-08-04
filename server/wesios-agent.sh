#!/usr/bin/env bash
#
# Агент WesiOS: сообщает приложению, чем занят сервер.
#
# ЗАЧЕМ ОН НУЖЕН. Загрузку процессора, память и диск чужой машины по сети
# узнать нельзя — сеть про это ничего не сообщает. Либо на сервере что-то
# эти цифры отдаёт, либо в приложении их не будет. Рисовать «примерно
# 45 %» было бы обманом, поэтому вместо этого — вот такой скрипт на
# двадцать строк.
#
# ЧТО ДЕЛАЕТ. Раз в минуту пишет JSON в каталог, который PocketBase уже
# раздаёт как статику. Приложение забирает его по адресу
#   https://<адрес>/wesios-status.json
# и показывает в модуле «Системный администратор».
#
# УСТАНОВКА (от root):
#   bash wesios-agent.sh --install
#
# СНЯТЬ:
#   bash wesios-agent.sh --uninstall

set -euo pipefail

OUT_DIR="${OUT_DIR:-/opt/pocketbase/pb_public}"
OUT_FILE="$OUT_DIR/wesios-status.json"

collect() {
  # Средняя загрузка за минуту — первая цифра из /proc/loadavg.
  local load1 cores mem_total_kb mem_avail_kb mem_total mem_used
  local disk_total disk_used uptime_sec

  load1=$(awk '{print $1}' /proc/loadavg)
  cores=$(nproc)

  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  # MemAvailable, а не MemFree: свободная память в Linux почти всегда близка
  # к нулю, потому что ядро занимает её под кеш и отдаёт по первому
  # требованию. По MemFree любой здоровый сервер выглядит задыхающимся.
  mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  mem_total=$(( mem_total_kb / 1024 ))
  mem_used=$(( (mem_total_kb - mem_avail_kb) / 1024 ))

  # Корневой раздел в гигабайтах.
  disk_total=$(df -BG --output=size / | tail -1 | tr -dc '0-9')
  disk_used=$(df -BG --output=used / | tail -1 | tr -dc '0-9')

  uptime_sec=$(awk '{print int($1)}' /proc/uptime)

  cat <<JSON
{
  "at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "load1": $load1,
  "cores": $cores,
  "mem_used_mb": $mem_used,
  "mem_total_mb": $mem_total,
  "disk_used_gb": $disk_used,
  "disk_total_gb": $disk_total,
  "uptime_sec": $uptime_sec
}
JSON
}

write_once() {
  mkdir -p "$OUT_DIR"
  # Пишем во временный файл и переименовываем: приложение не должно застать
  # файл на середине записи и получить обрезанный JSON.
  local tmp
  tmp="$(mktemp "$OUT_DIR/.wesios-status.XXXXXX")"
  collect > "$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$OUT_FILE"
}

install_timer() {
  local self
  self="$(readlink -f "$0")"
  install -m 0755 "$self" /usr/local/bin/wesios-agent.sh

  cat >/etc/systemd/system/wesios-agent.service <<UNIT
[Unit]
Description=WesiOS server agent (writes status JSON)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wesios-agent.sh --once
UNIT

  cat >/etc/systemd/system/wesios-agent.timer <<UNIT
[Unit]
Description=Run WesiOS server agent every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now wesios-agent.timer
  write_once

  cat <<TEXT

Готово. Файл: $OUT_FILE

В приложении: Ещё → Системный администратор → узел → Адрес агента:
  https://<ваш адрес>/wesios-status.json

ВАЖНО. Этот файл раздаётся всем, у кого есть ссылка: PocketBase не проверяет
вход для статики. В нём нет ничего секретного — загрузка, память, место на
диске и аптайм, — но это всё же сведения о вашем сервере. Если такое не
устраивает, отдавайте его через nginx с паролем или закройте адрес по IP.

TEXT
}

uninstall_timer() {
  systemctl disable --now wesios-agent.timer 2>/dev/null || true
  rm -f /etc/systemd/system/wesios-agent.timer \
        /etc/systemd/system/wesios-agent.service \
        /usr/local/bin/wesios-agent.sh "$OUT_FILE"
  systemctl daemon-reload
  echo "Агент снят."
}

case "${1:---once}" in
  --once)      write_once ;;
  --print)     collect ;;
  --install)   install_timer ;;
  --uninstall) uninstall_timer ;;
  *)
    echo "Использование: $0 [--once|--print|--install|--uninstall]" >&2
    exit 1
    ;;
esac
