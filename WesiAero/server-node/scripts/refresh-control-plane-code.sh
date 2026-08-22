#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This updater must run as root." >&2
  exit 1
fi

SOURCE_DIR="${1:?Path to current server-node source is required}"
INSTALL_DIR="${WESI_AERO_INSTALL_DIR:-/opt/wesi-aero/server-node}"
ENV_FILE="/etc/wesi-aero/control.env"
SERVICE="wesi-aero-control.service"

[[ -d "$SOURCE_DIR/src" && -s "$SOURCE_DIR/package.json" ]] || {
  echo "Invalid Wesi Aero server-node source: $SOURCE_DIR" >&2
  exit 1
}
[[ -s "$ENV_FILE" ]] || {
  echo "Existing Wesi Aero control-plane environment is missing." >&2
  exit 1
}

# Do not mutate database, credentials, profiles or payment settings here. This
# operation only replaces executable source so an incremental protocol deploy
# cannot accidentally reset live state.
install -d -m 755 "$INSTALL_DIR"
tmp="$(mktemp -d /opt/wesi-aero/.refresh.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
cp -a "$SOURCE_DIR"/. "$tmp/"

# Verify that the source being deployed understands the expanded protocol set.
for protocol in vless-reality vmess trojan shadowsocks hysteria2 tuic wireguard amneziawg; do
  grep -q "'$protocol'" "$tmp/src/repository.mjs" || {
    echo "Control-plane source does not support protocol: $protocol" >&2
    exit 1
  }
done

rm -rf "$INSTALL_DIR"/*
cp -a "$tmp"/. "$INSTALL_DIR"/
chown -R root:root "$INSTALL_DIR"
chmod -R o-w "$INSTALL_DIR"

systemctl restart "$SERVICE"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 2 http://127.0.0.1:8790/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
curl -fsS --max-time 5 http://127.0.0.1:8790/healthz | jq -e '.status == "ok"' >/dev/null
systemctl is-active --quiet "$SERVICE"

echo "Wesi Aero control-plane executable source refreshed without resetting state."
