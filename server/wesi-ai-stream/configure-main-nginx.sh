#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-/etc/nginx/sites-available/api.wesi-inc.ru}"
if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo -n); fi
command -v nginx >/dev/null 2>&1
[ -f "$SITE" ] || { echo "nginx site not found: $SITE" >&2; exit 2; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
"${SUDO[@]}" cat "$SITE" > "$TMP"

python3 - "$TMP" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding='utf-8')
start='# WESI_AI_STREAM_BEGIN'
end='# WESI_AI_STREAM_END'
if start in s:
    s=re.sub(r'\n?\s*# WESI_AI_STREAM_BEGIN.*?# WESI_AI_STREAM_END\s*\n?', '\n', s, flags=re.S)
block=r'''
    # WESI_AI_STREAM_BEGIN
    location = /api/wesi/ai/chat/stream {
        client_max_body_size 32m;
        proxy_pass http://127.0.0.1:8792/api/wesi/ai/chat/stream;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering on;
        proxy_cache off;
        gzip off;
        proxy_read_timeout 420s;
        proxy_send_timeout 120s;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header X-WesiOS-Session $http_x_wesios_session;
        add_header X-Accel-Buffering no always;
    }
    # WESI_AI_STREAM_END
'''
# Insert into the HTTPS server block that owns api.wesi-inc.ru.
match=re.search(r'server\s*\{(?P<body>.*?server_name\s+[^;]*\bapi\.wesi-inc\.ru\b[^;]*;.*?)(?=\n\})', s, flags=re.S)
if not match:
    raise SystemExit('Could not find api.wesi-inc.ru server block')
insert_at=match.end('body')
s=s[:insert_at]+block+s[insert_at:]
p.write_text(s, encoding='utf-8')
PY

"${SUDO[@]}" install -o root -g root -m 0644 "$TMP" "$SITE"
"${SUDO[@]}" nginx -t
"${SUDO[@]}" systemctl reload nginx
