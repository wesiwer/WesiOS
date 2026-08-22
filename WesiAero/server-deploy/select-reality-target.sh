#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-auto}"
CONFIG="${2:-$(cd "$(dirname "$0")" && pwd)/reality-targets.json}"

[ -f "$CONFIG" ] || { echo "target config not found: $CONFIG" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo 'python3 is required' >&2; exit 3; }
command -v openssl >/dev/null 2>&1 || { echo 'openssl is required' >&2; exit 3; }

read_profile() {
  python3 - "$CONFIG" "$PROFILE" <<'PY'
import json, sys
path, profile = sys.argv[1:]
data = json.load(open(path, encoding='utf-8'))
profiles = data.get('profiles', {})
item = profiles.get(profile)
if not isinstance(item, dict):
    raise SystemExit(f'unknown REALITY profile: {profile}')
if profile == 'auto':
    for host in item.get('candidates', []):
        if isinstance(host, str) and host:
            print('CANDIDATE\t' + host)
else:
    server = item.get('serverName')
    target = item.get('target')
    if not server or not target:
        raise SystemExit(f'profile {profile} requires explicit environment values')
    print('SELECTED\t' + server + '\t' + target)
PY
}

probe_host() {
  local host="$1"
  local start end elapsed output
  start="$(date +%s%3N)"
  if ! output="$(timeout 7 openssl s_client -connect "$host:443" -servername "$host" -tls1_3 -alpn h2 </dev/null 2>&1)"; then
    return 1
  fi
  end="$(date +%s%3N)"
  grep -q 'BEGIN CERTIFICATE' <<<"$output" || return 1
  grep -Eq 'Protocol *: *TLSv1\.3|New, TLSv1\.3' <<<"$output" || return 1
  elapsed=$((end - start))
  printf '%s\n' "$elapsed"
}

if [ "$PROFILE" = custom ]; then
  server="${WESI_AERO_REALITY_SERVER_NAME:-}"
  target="${WESI_AERO_REALITY_TARGET:-}"
  [ -n "$server" ] && [ -n "$target" ] || {
    echo 'custom profile requires WESI_AERO_REALITY_SERVER_NAME and WESI_AERO_REALITY_TARGET' >&2
    exit 4
  }
  printf 'SERVER_NAME=%s\nTARGET=%s\nPROFILE=%s\n' "$server" "$target" "$PROFILE"
  exit 0
fi

mapfile -t rows < <(read_profile)
if [ "$PROFILE" != auto ]; then
  IFS=$'\t' read -r kind server target <<<"${rows[0]:-}"
  [ "$kind" = SELECTED ] || { echo 'invalid preset' >&2; exit 5; }
  probe_host "$server" >/dev/null || { echo "preset target $server failed TLS1.3 validation" >&2; exit 6; }
  printf 'SERVER_NAME=%s\nTARGET=%s\nPROFILE=%s\n' "$server" "$target" "$PROFILE"
  exit 0
fi

best_host=''
best_ms=''
for row in "${rows[@]}"; do
  IFS=$'\t' read -r kind host <<<"$row"
  [ "$kind" = CANDIDATE ] || continue
  if ms="$(probe_host "$host")"; then
    echo "REALITY candidate $host: ${ms}ms" >&2
    if [ -z "$best_ms" ] || [ "$ms" -lt "$best_ms" ]; then
      best_ms="$ms"
      best_host="$host"
    fi
  else
    echo "REALITY candidate $host: rejected" >&2
  fi
done

[ -n "$best_host" ] || { echo 'no REALITY target candidate passed TLS1.3 validation' >&2; exit 7; }
printf 'SERVER_NAME=%s\nTARGET=%s:443\nPROFILE=auto\n' "$best_host" "$best_host"
