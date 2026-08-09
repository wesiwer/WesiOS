#!/usr/bin/env bash
set -euo pipefail

cp "$0" /tmp/fix_otp_login_01917.sh

git fetch origin main
git checkout -B main origin/main

printf '\n=== Existing corruption-related messages ===\n'
grep -RniE 'повреж|corrupt|damag' lib server test 2>/dev/null || true

python3 <<'PY'
from pathlib import Path

login = Path('lib/features/auth/login_screen.dart')
text = login.read_text(encoding='utf-8')
for signature in (
    '  Future<void> _sendCode() async {\n',
    '  Future<void> _submitOwnerEmail() async {\n',
    '  Future<void> _verifyCode() async {\n',
):
    guarded = signature + '    if (_busy) return;\n'
    if guarded not in text:
        if signature not in text:
            raise SystemExit(f'login guard anchor not found: {signature.strip()}')
        text = text.replace(signature, guarded, 1)
old = '''    if (!result.ok || result.identity == null) {
      setState(() {
        _busy = false;
        _error = result.error ?? (_ru ? 'Не удалось подтвердить вход' : 'Unable to verify sign-in');
      });
      return;
    }
'''
new = '''    if (!result.ok || result.identity == null) {
      final challengeEnded = _challengeEnded(result);
      setState(() {
        _busy = false;
        if (challengeEnded) {
          _challengeId = null;
          _maskedEmail = null;
          _needsEmailSetup = false;
          _code.clear();
          _error = _ru
              ? 'Эта попытка входа уже завершена. Запросите новый код.'
              : 'This sign-in attempt has ended. Request a new code.';
        } else {
          _error = result.error ??
              (_ru ? 'Не удалось подтвердить вход' : 'Unable to verify sign-in');
        }
      });
      return;
    }
'''
if old not in text:
    raise SystemExit('verify failure anchor not found')
text = text.replace(old, new, 1)
anchor = '''  Future<void> _finishLogin(PortalAppIdentity identity) async {
'''
helper = '''  bool _challengeEnded(PortalLoginResult result) {
    if (result.statusCode != 401) return false;
    final message = (result.error ?? '').toLowerCase();
    return message.contains('уже использован') ||
        message.contains('срок действия кода истёк') ||
        message.contains('слишком много неверных попыток') ||
        message.contains('проверка входа истекла') ||
        message.contains('эта попытка входа завершена') ||
        message.contains('challenge expired');
  }

'''
if helper not in text:
    if anchor not in text:
        raise SystemExit('challenge helper anchor not found')
    text = text.replace(anchor, helper + anchor, 1)
login.write_text(text, encoding='utf-8')

sync = Path('lib/core/sync/sync_endpoint.dart')
text = sync.read_text(encoding='utf-8')
old = '''    Map<String, dynamic>? loaded;
    try {
      loaded = _decodeSession(
        await _secureStorage.read(key: _secureSessionKey),
      );
    } catch (error) {
      debugPrint('WesiOS secure session read failed: $error');
    }
'''
new = '''    Map<String, dynamic>? loaded;
    String? secureRaw;
    try {
      secureRaw = await _secureStorage.read(key: _secureSessionKey);
      loaded = _decodeSession(secureRaw);
      if (secureRaw != null && secureRaw.isNotEmpty &&
          !_hasRevocableSessionShape(loaded)) {
        await _secureStorage.delete(key: _secureSessionKey);
        loaded = null;
      }
    } catch (error) {
      debugPrint('WesiOS secure session read failed: $error');
      try {
        await _secureStorage.delete(key: _secureSessionKey);
      } catch (_) {}
      loaded = null;
    }
'''
if old not in text:
    raise SystemExit('secure session init anchor not found')
text = text.replace(old, new, 1)
sync.write_text(text, encoding='utf-8')

team = Path('lib/features/team/services/team_service.dart')
text = team.read_text(encoding='utf-8')
anchor = '''  static Future<void> forgetUnrememberedSession() async {
'''
method = '''  static Future<void> repairLocalSessionReference() async {
    final box = _settings();
    if (box == null) return;
    final currentId = box.get(_currentKey);
    if (currentId is String && currentId.isNotEmpty && byId(currentId) == null) {
      await box.delete(_currentKey);
      await box.delete(_rememberKey);
      revision.value++;
    }
  }

'''
if method not in text:
    if anchor not in text:
        raise SystemExit('team repair anchor not found')
    text = text.replace(anchor, method + anchor, 1)
team.write_text(text, encoding='utf-8')

main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
old = '''  await SyncEndpoint.initializeSession();
  await TeamService.forgetUnrememberedSession();
'''
new = '''  await SyncEndpoint.initializeSession();
  await TeamService.repairLocalSessionReference();
  await TeamService.forgetUnrememberedSession();
'''
if old not in text:
    raise SystemExit('main session repair anchor not found')
main.write_text(text, encoding='utf-8')

auth = Path('server/pb_hooks/wesi_auth_bootstrap.pb.js')
text = auth.read_text(encoding='utf-8')
old = '''  sendCode(email, displayName, purpose, challengeId, challenge, payload);
  return e.json(200, {
'''
new = '''  sendCode(email, displayName, purpose, challengeId, challenge, payload);

  // Only the newest successfully delivered OTP remains usable for this
  // account and purpose. This prevents an older email from being paired with
  // a newer client challenge after retries/reactivation.
  try {
    const records = e.app.findRecordsByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && deleted=false",
      "-stamp",
      500,
      0,
    );
    for (const item of records) {
      if (item.id === challenge.id) continue;
      try {
        const model = new DynamicModel({
          "kind": "", "userId": "", "purpose": "", "usedAt": "",
        });
        item.unmarshalJSONField("payload", model);
        if (String(model.kind || "") !== "otp" ||
            String(model.userId || "") !== user.id ||
            String(model.purpose || "app") !== purpose ||
            String(model.usedAt || "")) {
          continue;
        }
        item.set("deleted", true);
        item.set("stamp", new Date().toISOString());
        e.app.save(item);
      } catch (_) {}
    }
  } catch (_) {}

  return e.json(200, {
'''
if old not in text:
    raise SystemExit('start-v2 delivery anchor not found')
text = text.replace(old, new, 1)
if '2026-08-09.owner-email-v10' not in text:
    raise SystemExit('unexpected auth bootstrap version')
text = text.replace('2026-08-09.owner-email-v10', '2026-08-09.owner-email-v11')
auth.write_text(text, encoding='utf-8')

security = Path('server/pb_hooks/wesi_security.pb.js')
text = security.read_text(encoding='utf-8')
old = '''      const model = new DynamicModel({
        "kind": "", "userId": "", "email": "", "fullName": "", "name": "",
        "id": "", "login": "", "usedAt": "", "sentAt": "",
      });
'''
new = '''      const model = new DynamicModel({
        "kind": "", "userId": "", "employeeId": "", "email": "",
        "fullName": "", "name": "", "id": "", "login": "",
        "usedAt": "", "sentAt": "",
      });
'''
if old not in text:
    raise SystemExit('legacy security valueObject model anchor not found')
text = text.replace(old, new, 1)
old = '''        "kind": String(model.kind || ""), "userId": String(model.userId || ""),
        "email": String(model.email || ""), "fullName": String(model.fullName || ""),
'''
new = '''        "kind": String(model.kind || ""), "userId": String(model.userId || ""),
        "employeeId": String(model.employeeId || ""),
        "email": String(model.email || ""), "fullName": String(model.fullName || ""),
'''
if old not in text:
    raise SystemExit('legacy security valueObject return anchor not found')
text = text.replace(old, new, 1)
old = '''  if (!challenge) throw new UnauthorizedError("Код недействителен или уже использован");

  const payload = valueObject(challenge, "payload");
'''
new = '''  if (!challenge) {
    let previous = null;
    try {
      previous = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner='__wesios_security__' && coll='security' && rid='otp:" + challengeId + "'",
      );
    } catch (_) {
      previous = null;
    }
    if (previous) {
      const previousPayload = valueObject(previous, "payload");
      if (previousPayload.usedAt) {
        throw new UnauthorizedError("Код уже использован. Запросите новый код");
      }
      throw new UnauthorizedError("Эта попытка входа завершена. Запросите новый код");
    }
    throw new UnauthorizedError("Проверка входа истекла. Запросите новый код");
  }

  const payload = valueObject(challenge, "payload");
'''
if old not in text:
    raise SystemExit('verify missing challenge anchor not found')
text = text.replace(old, new, 1)
if '2026-08-09.security-mail-v8' not in text:
    raise SystemExit('unexpected security hook version')
text = text.replace('2026-08-09.security-mail-v8', '2026-08-09.security-mail-v9', 1)
security.write_text(text, encoding='utf-8')

pubspec = Path('pubspec.yaml')
p = pubspec.read_text(encoding='utf-8')
if 'version: 0.19.16+64' not in p:
    raise SystemExit('unexpected pubspec version')
pubspec.write_text(p.replace('version: 0.19.16+64', 'version: 0.19.17+65', 1), encoding='utf-8')

appv = Path('lib/core/constants/app_version.dart')
a = appv.read_text(encoding='utf-8')
if "static const String number = '0.19.16';" not in a or 'static const int build = 64;' not in a:
    raise SystemExit('unexpected AppVersion')
a = a.replace("static const String number = '0.19.16';", "static const String number = '0.19.17';", 1)
a = a.replace('static const int build = 64;', 'static const int build = 65;', 1)
appv.write_text(a, encoding='utf-8')

test = Path('test/otp_login_regression_test.dart')
test.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OTP verify cannot be submitted twice while a request is in flight', () {
    final source = File('lib/features/auth/login_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _verifyCode() async {');
    expect(start, isNonNegative);
    final end = start + 220 < source.length ? start + 220 : source.length;
    final window = source.substring(start, end);
    expect(window, contains('if (_busy) return;'));
  });

  test('dead OTP challenge returns to a fresh sign-in flow', () {
    final source = File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(source, contains('bool _challengeEnded(PortalLoginResult result)'));
    expect(source, contains("message.contains('уже использован')"));
    expect(source, contains('_challengeId = null;'));
  });

  test('new start-v2 OTP invalidates older pending OTPs', () {
    final source = File('server/pb_hooks/wesi_auth_bootstrap.pb.js').readAsStringSync();
    expect(source, contains('Only the newest successfully delivered OTP remains usable'));
    expect(source, contains('item.set("deleted", true);'));
    expect(source, contains('2026-08-09.owner-email-v11'));
  });

  test('legacy security login reads employeeId and dead challenges are explicit', () {
    final source = File('server/pb_hooks/wesi_security.pb.js').readAsStringSync();
    expect(source, contains('"employeeId": String(model.employeeId || "")'));
    expect(source, contains('Код уже использован. Запросите новый код'));
    expect(source, contains('2026-08-09.security-mail-v9'));
  });
}
''', encoding='utf-8')
PY

dart format \
  lib/features/auth/login_screen.dart \
  lib/core/sync/sync_endpoint.dart \
  lib/features/team/services/team_service.dart \
  lib/main.dart \
  lib/core/constants/app_version.dart \
  test/otp_login_regression_test.dart
node --check server/pb_hooks/wesi_auth_bootstrap.pb.js
node --check server/pb_hooks/wesi_security.pb.js

grep -q 'if (_busy) return;' lib/features/auth/login_screen.dart
grep -q 'Only the newest successfully delivered OTP remains usable' server/pb_hooks/wesi_auth_bootstrap.pb.js
grep -q '2026-08-09.security-mail-v9' server/pb_hooks/wesi_security.pb.js
grep -q '^version: 0.19.17+65$' pubspec.yaml

flutter pub get
flutter analyze --no-fatal-infos
flutter test

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/features/auth/login_screen.dart \
  lib/core/sync/sync_endpoint.dart \
  lib/features/team/services/team_service.dart \
  lib/main.dart \
  lib/core/constants/app_version.dart \
  server/pb_hooks/wesi_auth_bootstrap.pb.js \
  server/pb_hooks/wesi_security.pb.js \
  test/otp_login_regression_test.dart \
  pubspec.yaml
git commit -m 'fix(auth): harden employee OTP login + 0.19.17+65'
git push origin HEAD:main

started=$(date -u +%s)
gh workflow run deploy-employee-portal.yml --repo "$GITHUB_REPOSITORY" --ref main
portal_run=''
for attempt in $(seq 1 60); do
  runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs?event=workflow_dispatch&per_page=50")
  portal_run=$(printf '%s' "$runs" | jq -r --argjson started "$started" '[.workflow_runs[] | select(.name == "Deploy employee portal") | select((.created_at | fromdateiso8601) >= ($started - 5))] | sort_by(.created_at) | last | .id // empty')
  [ -n "$portal_run" ] && break
  sleep 3
done
[ -n "$portal_run" ] || { echo 'Deploy employee portal run not found' >&2; exit 1; }
for attempt in $(seq 1 120); do
  run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$portal_run")
  status=$(printf '%s' "$run" | jq -r '.status')
  conclusion=$(printf '%s' "$run" | jq -r '.conclusion // ""')
  echo "portal deploy: $status $conclusion"
  if [ "$status" = completed ]; then
    [ "$conclusion" = success ] && break
    exit 1
  fi
  sleep 6
done
[ "$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$portal_run" --jq '.conclusion // ""')" = success ]

for attempt in $(seq 1 30); do
  auth_body=$(curl -fsS --max-time 20 https://api.wesi-inc.ru/api/wesi/auth/version || true)
  sec_body=$(curl -fsS --max-time 20 https://api.wesi-inc.ru/api/wesi/security/version || true)
  echo "$auth_body"
  echo "$sec_body"
  if grep -q '2026-08-09.owner-email-v11' <<<"$auth_body" && \
     grep -q '2026-08-09.security-mail-v9' <<<"$sec_body"; then
    break
  fi
  sleep 2
done
grep -q '2026-08-09.owner-email-v11' <<<"$auth_body"
grep -q '2026-08-09.security-mail-v9' <<<"$sec_body"

started=$(date -u +%s)
gh workflow run publish-wesios-production.yml \
  --repo "$GITHUB_REPOSITORY" \
  --ref main \
  -f notes='Исправлен вход сотрудников по коду из почты: исключена двойная отправка одного OTP, новый код закрывает старые попытки входа, истёкший/использованный challenge автоматически сбрасывается. Повреждённые локальные данные сессии теперь очищаются автоматически.'
release_run=''
for attempt in $(seq 1 60); do
  runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs?event=workflow_dispatch&per_page=50")
  release_run=$(printf '%s' "$runs" | jq -r --argjson started "$started" '[.workflow_runs[] | select(.name == "Publish WesiOS Production") | select((.created_at | fromdateiso8601) >= ($started - 5))] | sort_by(.created_at) | last | .id // empty')
  [ -n "$release_run" ] && break
  sleep 5
done
[ -n "$release_run" ] || { echo 'Production release run not found' >&2; exit 1; }
for attempt in $(seq 1 300); do
  run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$release_run")
  status=$(printf '%s' "$run" | jq -r '.status')
  conclusion=$(printf '%s' "$run" | jq -r '.conclusion // ""')
  echo "production release: $status $conclusion"
  if [ "$status" = completed ]; then
    [ "$conclusion" = success ] && exit 0
    exit 1
  fi
  sleep 15
done
exit 1
