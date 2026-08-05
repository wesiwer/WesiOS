#!/usr/bin/env bash
# Одноразовая подготовка прав для автоматического портала сотрудников.
# Запускать от root на российском сервере:
#
#   curl -fsSL https://raw.githubusercontent.com/wesiwer/WesiOS/main/server/bootstrap-employee-portal.sh | bash
#
# После этого GitHub Actions под пользователем wesios-deploy может обновлять
# сайт, артефакты и PocketBase hooks без root-доступа.

set -euo pipefail

DEPLOY_USER="${WESI_DEPLOY_USER:-wesios-deploy}"
PB_USER="${WESI_PB_USER:-pocketbase}"
PB_ROOT="${WESI_PB_ROOT:-/opt/pocketbase}"
ARTIFACTS="$PB_ROOT/pb_public/artifacts"
HOOKS="$PB_ROOT/pb_hooks"

if [[ "$(id -u)" != 0 ]]; then
  echo "Нужны права root." >&2
  exit 1
fi

id "$DEPLOY_USER" >/dev/null 2>&1 || {
  echo "Нет пользователя $DEPLOY_USER. Сначала создайте пользователя деплоя." >&2
  exit 1
}
id "$PB_USER" >/dev/null 2>&1 || {
  echo "Нет пользователя $PB_USER. PocketBase установлен не по стандартной схеме WesiOS." >&2
  exit 1
}

# Один общий системный group — PocketBase читает, deploy-пользователь пишет.
usermod -aG "$PB_USER" "$DEPLOY_USER"

install -d -o "$PB_USER" -g "$PB_USER" -m 2775 "$PB_ROOT/pb_public"
install -d -o "$PB_USER" -g "$PB_USER" -m 2775 "$ARTIFACTS"
install -d -o "$PB_USER" -g "$PB_USER" -m 2775 "$HOOKS"

# Уже существующие каталоги могли быть созданы с 0755 и чужим владельцем.
chown -R "$PB_USER:$PB_USER" "$ARTIFACTS" "$HOOKS"
find "$ARTIFACTS" "$HOOKS" -type d -exec chmod 2775 {} +
find "$ARTIFACTS" "$HOOKS" -type f -exec chmod 0664 {} +

# ACL делает права действующими и для текущих, и для будущих файлов даже если
# отдельный скрипт однажды создаст их с более строгим umask.
if command -v setfacl >/dev/null 2>&1; then
  setfacl -Rm "u:$DEPLOY_USER:rwx,u:$PB_USER:rwx" "$ARTIFACTS" "$HOOKS"
  setfacl -Rdm "u:$DEPLOY_USER:rwx,u:$PB_USER:rwx" "$ARTIFACTS" "$HOOKS"
fi

systemctl restart pocketbase

cat <<EOF

Готово.

Каталог сборок: $ARTIFACTS
Каталог hooks:   $HOOKS
Пользователь:    $DEPLOY_USER (добавлен в группу $PB_USER)

Новые SSH-сеансы уже получат права. Повторите workflow "Deploy employee portal".
Основной адрес после выкладки: https://api.wesi-inc.ru/portal/
EOF
