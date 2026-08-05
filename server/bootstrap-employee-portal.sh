#!/usr/bin/env bash
# Одноразовая подготовка прав для автоматического портала сотрудников.
# Запускать от root на российском сервере:
#
#   curl -fsSL https://raw.githubusercontent.com/wesiwer/WesiOS/main/server/bootstrap-employee-portal.sh -o /root/bootstrap-employee-portal.sh
#   bash /root/bootstrap-employee-portal.sh
#
# После этого GitHub Actions под пользователем wesios-deploy может обновлять
# сайт, артефакты и PocketBase hooks без root-доступа.

set -euo pipefail

DEPLOY_USER="${WESI_DEPLOY_USER:-wesios-deploy}"
PB_ROOT="${WESI_PB_ROOT:-/opt/pocketbase}"
ARTIFACTS="$PB_ROOT/pb_public/artifacts"
HOOKS="$PB_ROOT/pb_hooks"
SHARED_GROUP="${WESI_DEPLOY_GROUP:-wesi-deploy}"

if [[ "$(id -u)" != 0 ]]; then
  echo "Нужны права root." >&2
  exit 1
fi

id "$DEPLOY_USER" >/dev/null 2>&1 || {
  echo "Нет пользователя $DEPLOY_USER. Сначала создайте пользователя деплоя." >&2
  exit 1
}

# Определяем реального пользователя systemd-сервиса. На текущем сервере
# PocketBase работает от root, поэтому требовать отдельного пользователя
# pocketbase было ошибкой.
PB_SERVICE_USER="$(systemctl show pocketbase --property=User --value 2>/dev/null || true)"
PB_SERVICE_GROUP="$(systemctl show pocketbase --property=Group --value 2>/dev/null || true)"
PB_SERVICE_USER="${PB_SERVICE_USER:-root}"
PB_SERVICE_GROUP="${PB_SERVICE_GROUP:-$PB_SERVICE_USER}"

if ! id "$PB_SERVICE_USER" >/dev/null 2>&1; then
  echo "Пользователь сервиса PocketBase '$PB_SERVICE_USER' не существует." >&2
  exit 1
fi

getent group "$SHARED_GROUP" >/dev/null 2>&1 || groupadd --system "$SHARED_GROUP"
usermod -aG "$SHARED_GROUP" "$DEPLOY_USER"

# PocketBase, запущенный от root, читает любые эти файлы. Для будущего
# перехода на отдельного пользователя также добавляем его в общую группу.
if [[ "$PB_SERVICE_USER" != root ]]; then
  usermod -aG "$SHARED_GROUP" "$PB_SERVICE_USER"
fi

install -d -o root -g "$SHARED_GROUP" -m 2775 "$PB_ROOT/pb_public"
install -d -o root -g "$SHARED_GROUP" -m 2775 "$ARTIFACTS"
install -d -o root -g "$SHARED_GROUP" -m 2775 "$HOOKS"

# Уже существующие каталоги могли быть созданы с 0755 и другой группой.
chown -R root:"$SHARED_GROUP" "$ARTIFACTS" "$HOOKS"
find "$ARTIFACTS" "$HOOKS" -type d -exec chmod 2775 {} +
find "$ARTIFACTS" "$HOOKS" -type f -exec chmod 0664 {} +

# ACL сохраняет права и для будущих файлов независимо от umask скриптов.
if command -v setfacl >/dev/null 2>&1; then
  setfacl -Rm "u:$DEPLOY_USER:rwx,g:$SHARED_GROUP:rwx" "$ARTIFACTS" "$HOOKS"
  setfacl -Rdm "u:$DEPLOY_USER:rwx,g:$SHARED_GROUP:rwx" "$ARTIFACTS" "$HOOKS"
fi

systemctl restart pocketbase
systemctl is-active --quiet pocketbase || {
  echo "PocketBase не запустился после изменения прав." >&2
  systemctl status pocketbase --no-pager || true
  exit 1
}

cat <<EOF

Готово.

PocketBase service user: $PB_SERVICE_USER
Каталог сборок:         $ARTIFACTS
Каталог hooks:           $HOOKS
Общая группа:            $SHARED_GROUP
Пользователь деплоя:     $DEPLOY_USER

Важно: уже открытая SSH-сессия пользователя $DEPLOY_USER не увидит новую
группу. GitHub Actions создаёт новый сеанс, поэтому там права применятся сразу.

Теперь повторите workflow "Deploy employee portal".
Основной адрес после выкладки: https://api.wesi-inc.ru/portal/
EOF
