#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://api.wesi-inc.ru}"
BASE_URL="${BASE_URL%/}"

probe_json_route() {
  local method="$1"
  local path="$2"
  local body="$3"
  local label="$4"
  local response_file headers_file code content_type
  response_file="$(mktemp)"
  headers_file="$(mktemp)"
  trap 'rm -f "$response_file" "$headers_file"' RETURN

  code="$(curl -sS --max-time 20 -D "$headers_file" -o "$response_file" -w '%{http_code}' \
    -X "$method" "$BASE_URL$path" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    --data "$body" || true)"

  if [ "$code" != '401' ] && [ "$code" != '403' ]; then
    echo "ERROR: $label route is not registered/protected at $BASE_URL$path (HTTP $code)" >&2
    head -c 800 "$response_file" >&2 || true
    echo >&2
    exit 1
  fi

  content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' "$headers_file")"
  case "${content_type,,}" in
    application/json*|application/problem+json*) ;;
    *)
      echo "ERROR: $label returned non-JSON Content-Type '$content_type' (HTTP $code)" >&2
      head -c 800 "$response_file" >&2 || true
      echo >&2
      exit 1
      ;;
  esac

  python3 - "$response_file" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
raw = path.read_text(encoding='utf-8')
value = json.loads(raw)
if not isinstance(value, dict):
    raise SystemExit('response JSON root must be an object')
PY

  echo "OK: $label protected JSON route (HTTP $code)"
  rm -f "$response_file" "$headers_file"
  trap - RETURN
}

probe_json_route POST /api/wesi/ai/chat \
  '{"persona":"zane","tier":"fast","message":"stage14-route-probe"}' \
  'Wesi AI Chat'
probe_json_route POST /api/wesi/ai/lobby \
  '{"persona":"lobby","tier":"fast","lobbyMode":"smart","message":"stage14-route-probe"}' \
  'Wesi AI Lobby'

echo "WESI_AI_MAIN_ROUTE_CONTRACT_OK base=$BASE_URL"
