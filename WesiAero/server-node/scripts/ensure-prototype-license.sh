#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${WESI_AERO_STATE_DIR:-/var/lib/wesi-aero}"
ENV_FILE="${WESI_AERO_ENV_FILE:-/etc/wesi-aero/control.env}"
CONTROL_URL="${WESI_AERO_LOCAL_CONTROL_URL:-http://127.0.0.1:8790}"
KEY_FILE="$STATE_DIR/prototype-license.key"

[[ -r "$ENV_FILE" ]] || {
  echo "Wesi Aero control env is missing: $ENV_FILE" >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${WESI_AERO_ADMIN_TOKEN:?WESI_AERO_ADMIN_TOKEN is missing from control.env}"

license_id_from_key() {
  local key="$1"
  if [[ ! "$key" =~ ^WA1-([0-9A-Fa-f]{32})-([A-Za-z0-9_-]{24,64})$ ]]; then
    return 1
  fi
  local compact="${BASH_REMATCH[1],,}"
  printf '%s-%s-%s-%s-%s\n' \
    "${compact:0:8}" \
    "${compact:8:4}" \
    "${compact:12:4}" \
    "${compact:16:4}" \
    "${compact:20:12}"
}

admin_get() {
  curl -fsS --max-time 10 \
    -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
    "$CONTROL_URL$1"
}

admin_delete() {
  curl -fsS --max-time 10 \
    -X DELETE \
    -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
    "$CONTROL_URL$1" >/dev/null
}

create_prototype_license() {
  local response key
  response="$(curl -fsS --max-time 10 \
    -X POST \
    -H "x-admin-token: $WESI_AERO_ADMIN_TOKEN" \
    -H 'content-type: application/json' \
    --data '{"planId":"aero-flex","ipMode":"shared","deviceLimit":5,"durationDays":365,"note":"Wesi Aero prototype access"}' \
    "$CONTROL_URL/v1/admin/licenses")"
  key="$(printf '%s' "$response" | jq -r '.key // empty')"
  license_id_from_key "$key" >/dev/null || {
    echo "Control plane did not issue a valid prototype license." >&2
    exit 1
  }
  install -m 600 /dev/null "$KEY_FILE"
  printf '%s\n' "$key" > "$KEY_FILE"
  printf '%s' "$key"
}

current_key=""
if [[ -s "$KEY_FILE" ]]; then
  current_key="$(tr -d '\r\n' < "$KEY_FILE")"
fi

valid=false
license_id=""
if license_id="$(license_id_from_key "$current_key" 2>/dev/null)"; then
  server_key="$(admin_get "/v1/admin/licenses/$license_id/key" 2>/dev/null | jq -r '.key // empty' || true)"
  if [[ -n "$server_key" && "$server_key" == "$current_key" ]]; then
    valid=true
  fi
fi

if [[ "$valid" != true ]]; then
  echo "Prototype license file is stale or missing; issuing a fresh server-backed key." >&2
  current_key="$(create_prototype_license)"
  license_id="$(license_id_from_key "$current_key")"
fi

# Prototype installs are updated frequently and Android may generate a new
# secure device id after reinstall/data reset. Keep the same key stable, but
# reclaim old prototype-only device seats if all five slots are already used.
devices_json="$(admin_get "/v1/admin/licenses/$license_id/devices")"
device_count="$(printf '%s' "$devices_json" | jq 'length')"
if [[ "$device_count" -ge 5 ]]; then
  echo "Prototype license has $device_count bound devices; reclaiming stale prototype seats." >&2
  while IFS= read -r device_id; do
    [[ -n "$device_id" ]] || continue
    # Device IDs are validated by the server to [A-Za-z0-9._:-], so they are
    # already safe as a single URL path segment and need no external encoder.
    admin_delete "/v1/admin/licenses/$license_id/devices/$device_id"
  done < <(printf '%s' "$devices_json" | jq -r '.[].deviceId')
fi

# Final server-side equality check. A Live APK must never be produced with a
# local file that is not the exact key currently stored by the control plane.
server_key="$(admin_get "/v1/admin/licenses/$license_id/key" | jq -r '.key // empty')"
if [[ -z "$server_key" || "$server_key" != "$current_key" ]]; then
  echo "Prototype license verification failed after repair." >&2
  exit 1
fi

chmod 600 "$KEY_FILE"
printf '%s\n' "$current_key"
