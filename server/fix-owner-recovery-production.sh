#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/pocketbase
HOOKS="$ROOT/pb_hooks"
SECURITY="$HOOKS/wesi_security.pb.js"
RECOVERY_HOOK="$HOOKS/wesi_owner_recovery.pb.js"
FLAG="$ROOT/.wesi-owner-recovery.json"
OLD_FLAG="$HOOKS/.wesi-owner-recovery.json"
CODE=734821
USER_ID=ex7bwkwp9e1l62o
LOGIN=WesiOff
PASSWORD='WesiTemp-8264-K7mQ'

make_flag() {
  EXPIRES="$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"userId":"%s","code":"%s","expiresAt":"%s"}\n' \
    "$USER_ID" "$CODE" "$EXPIRES" > "$FLAG"
  chmod 600 "$FLAG"
}

echo '=== 1. Stop PocketBase and install fixed hooks ==='
systemctl stop pocketbase.service
rm -f "$OLD_FLAG" "$FLAG"

curl -fL \
  https://raw.githubusercontent.com/wesiwer/WesiOS/main/server/pb_hooks/wesi_owner_recovery.pb.js \
  -o "$RECOVERY_HOOK"

curl -fL \
  https://raw.githubusercontent.com/wesiwer/WesiOS/main/server/patch-wesi-security-payload-parser.sh \
  -o /root/patch-wesi-security-payload-parser.sh
chmod +x /root/patch-wesi-security-payload-parser.sh
bash /root/patch-wesi-security-payload-parser.sh "$SECURITY"

# PocketBase JSVM newStaticAuthToken() expects Go time.Duration, i.e.
# nanoseconds, not seconds. Passing durationSeconds directly produced a token
# valid for only a fraction of a second, so /verify succeeded but the very next
# authenticated /bootstrap request rejected the already-expired token.
python3 - "$SECURITY" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = '"token": user.newStaticAuthToken(durationSeconds),'
new = '"token": user.newStaticAuthToken(durationSeconds * 1000000000),'
if new in s:
    print('AUTH TOKEN DURATION PATCH: already installed')
elif old in s:
    s = s.replace(old, new, 1)
    p.write_text(s)
    print('AUTH TOKEN DURATION PATCH: installed')
else:
    print('AUTH TOKEN DURATION PATCH: target not found')
    sys.exit(1)
PY

grep -n 'newStaticAuthToken' "$SECURITY" | head -10

echo '=== 2. Start PocketBase ==='
systemctl start pocketbase.service
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8090/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8090/api/health >/dev/null

if journalctl -u pocketbase.service --since '-1 minute' --no-pager | grep -q 'failed to execute wesi_owner_recovery'; then
  echo 'RECOVERY HOOK LOAD FAILED'
  journalctl -u pocketbase.service -n 80 --no-pager
  exit 1
fi

echo 'POCKETBASE + RECOVERY HOOK: OK'

echo '=== 3. Server-side recovery test ==='
make_flag
PID_BEFORE="$(systemctl show -p MainPID --value pocketbase.service)"

START="$(curl -sS -X POST \
  http://127.0.0.1:8090/api/wesi/auth/start-v2 \
  -H 'Content-Type: application/json' \
  --data "{\"login\":\"$LOGIN\",\"password\":\"$PASSWORD\",\"purpose\":\"app\"}")"
export START

CHALLENGE="$(python3 - <<'PY'
import json, os
try:
    print(json.loads(os.environ['START']).get('challengeId',''))
except Exception:
    print('')
PY
)"

if [ -z "$CHALLENGE" ]; then
  echo 'START-V2 FAILED:'
  echo "$START"
  exit 1
fi

echo "START-V2 OK: ${CHALLENGE:0:10}..."
sleep 1

PID_AFTER="$(systemctl show -p MainPID --value pocketbase.service)"
if [ "$PID_BEFORE" != "$PID_AFTER" ]; then
  echo "ERROR: PocketBase restarted during recovery ($PID_BEFORE -> $PID_AFTER)"
  journalctl -u pocketbase.service -n 80 --no-pager
  exit 1
fi
curl -fsS http://127.0.0.1:8090/api/health >/dev/null
echo 'NO HOT-RESTART: OK'

# Print the exact stored OTP payload for diagnostics before verification.
RID="otp:$CHALLENGE"
RAW_PAYLOAD="$(sqlite3 "$ROOT/pb_data/data.db" "SELECT payload FROM wesios_records WHERE owner='__wesios_security__' AND coll='security' AND rid='$RID' AND deleted=0 LIMIT 1;")"
export RAW_PAYLOAD
python3 - <<'PY'
import json, os, sys
raw=os.environ.get('RAW_PAYLOAD','')
try:
    d=json.loads(raw)
    while isinstance(d,str):
        d=json.loads(d)
except Exception as exc:
    print('STORED OTP PAYLOAD INVALID:', repr(raw), exc)
    sys.exit(1)
print('STORED OTP expiresAt:', d.get('expiresAt'))
print('STORED OTP delivery:', d.get('delivery'))
PY

export CHALLENGE
VERIFY_BODY="$(python3 - <<'PY'
import json, os
print(json.dumps({
  'challengeId': os.environ['CHALLENGE'],
  'code': '734821',
  'remember': True,
  'device': {'platform':'linux','deviceName':'WesiOS server recovery test'}
}))
PY
)"

VERIFY="$(curl -sS -X POST \
  http://127.0.0.1:8090/api/wesi/auth/verify \
  -H 'Content-Type: application/json' \
  --data "$VERIFY_BODY")"
export VERIFY

readarray -t AUTH_DATA < <(python3 - <<'PY'
import json, os, sys
raw=os.environ['VERIFY']
try:
    d=json.loads(raw)
except Exception:
    print('')
    print('')
    print('')
    raise SystemExit
if not (d.get('token') and d.get('sessionId') and d.get('userId')):
    print('')
    print('')
    print('')
    raise SystemExit
print(d['token'])
print(d['sessionId'])
print(d['userId'])
PY
)

TOKEN="${AUTH_DATA[0]:-}"
SESSION_ID="${AUTH_DATA[1]:-}"
VERIFIED_USER_ID="${AUTH_DATA[2]:-}"

if [ -z "$TOKEN" ] || [ -z "$SESSION_ID" ] || [ -z "$VERIFIED_USER_ID" ]; then
  echo 'VERIFY FAILED:'
  echo "$VERIFY"
  exit 1
fi

echo 'VERIFY OK'
echo "userId: $VERIFIED_USER_ID"
echo "sessionId length: ${#SESSION_ID}"

echo '=== 4. Validate issued PocketBase auth token with bootstrap ==='
BOOTSTRAP="$(curl -sS -w '\nHTTP_CODE:%{http_code}' \
  http://127.0.0.1:8090/api/wesi/app/bootstrap \
  -H "Authorization: $TOKEN" \
  -H "X-WesiOS-Session: $SESSION_ID")"
export BOOTSTRAP

python3 - <<'PY'
import json, os, sys
raw=os.environ['BOOTSTRAP']
body, sep, status = raw.rpartition('\nHTTP_CODE:')
if not sep:
    print('BOOTSTRAP FAILED: missing HTTP status')
    print(raw)
    sys.exit(1)
try:
    code=int(status.strip())
except Exception:
    print('BOOTSTRAP FAILED: invalid HTTP status', repr(status))
    sys.exit(1)
if code != 200:
    print('BOOTSTRAP FAILED HTTP', code)
    print(body)
    sys.exit(1)
try:
    d=json.loads(body)
except Exception:
    print('BOOTSTRAP FAILED: non-JSON response')
    print(body)
    sys.exit(1)
if d.get('owner') is not True:
    print('BOOTSTRAP FAILED: response is not owner profile')
    print(json.dumps(d, ensure_ascii=False))
    sys.exit(1)
print('BOOTSTRAP AUTH TOKEN: OK')
print('BOOTSTRAP OWNER: OK')
print('login:', d.get('login'))
PY

echo '=== 5. Fresh phone recovery ==='
make_flag

echo
echo '=================================================='
echo 'FULL SERVER RECOVERY + AUTH TEST: OK'
echo "PHONE RECOVERY READY до $EXPIRES"
echo 'Нажми в приложении: Войти как владелец — временно'
echo '=================================================='
