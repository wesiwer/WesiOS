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
import json, os, sys, datetime
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

python3 - <<'PY'
import json, os, sys
raw=os.environ['VERIFY']
try:
    d=json.loads(raw)
except Exception:
    print('VERIFY NON-JSON:', raw)
    sys.exit(1)
if not (d.get('token') and d.get('sessionId') and d.get('userId')):
    print('VERIFY FAILED:', json.dumps(d, ensure_ascii=False))
    sys.exit(1)
print('VERIFY OK')
print('userId:', d.get('userId'))
print('sessionId length:', len(d.get('sessionId','')))
PY

echo '=== 4. Fresh phone recovery ==='
make_flag

echo
echo '=================================================='
echo 'FULL SERVER RECOVERY TEST: OK'
echo "PHONE RECOVERY READY до $EXPIRES"
echo 'Нажми в приложении: Войти как владелец — временно'
echo '=================================================='
