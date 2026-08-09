#!/usr/bin/env bash
set -euo pipefail

python3 <<'PY'
from pathlib import Path

# 1. Fix login source of truth: preserve employeeId from portal-account payload.
auth = Path('server/pb_hooks/wesi_auth_bootstrap.pb.js')
text = auth.read_text(encoding='utf-8')
old = '''      const model = new DynamicModel({"email": "", "fullName": "", "name": ""});
      record.unmarshalJSONField("payload", model);
      return {
        "email": String(model.email || ""),
        "fullName": String(model.fullName || ""),
        "name": String(model.name || ""),
      };'''
new = '''      const model = new DynamicModel({
        "employeeId": "",
        "email": "",
        "fullName": "",
        "name": "",
      });
      record.unmarshalJSONField("payload", model);
      return {
        "employeeId": String(model.employeeId || ""),
        "email": String(model.email || ""),
        "fullName": String(model.fullName || ""),
        "name": String(model.name || ""),
      };'''
if old not in text:
    raise SystemExit('start-v2 valueObject anchor not found')
text = text.replace(old, new, 1)
if '2026-08-09.owner-email-v9' not in text:
    raise SystemExit('unexpected auth hook version')
text = text.replace('2026-08-09.owner-email-v9', '2026-08-09.owner-email-v10')
auth.write_text(text, encoding='utf-8')

# 2. Make provision fail closed: report success only after credentials and link
# can be read back exactly as the login flow expects them.
portal = Path('server/pb_hooks/employee_portal.pb.js')
text = portal.read_text(encoding='utf-8')
old = '''  e.app.save(link);

  return e.json(created ? 201 : 200, {
    "id": record.id,
    "email": record.getString("email"),
    "name": record.getString("name"),
    "login": login,
    "created": created,
    "linked": true,
  });'''
new = '''  e.app.save(link);

  let verifiedUser = null;
  try {
    verifiedUser = e.app.findAuthRecordByEmail("users", email);
  } catch (_) {
    verifiedUser = null;
  }
  if (!verifiedUser || verifiedUser.id !== record.id || !verifiedUser.validatePassword(password)) {
    throw new InternalServerError("Сервер не подтвердил созданные данные входа сотрудника");
  }

  let verifiedLink = null;
  try {
    verifiedLink = e.app.findFirstRecordByFilter(
      "wesios_records",
      "coll='system' && rid='" + linkRid + "' && deleted=false",
    );
  } catch (_) {
    verifiedLink = null;
  }
  if (!verifiedLink || verifiedLink.getString("owner") !== e.auth.id) {
    throw new InternalServerError("Сервер не подтвердил привязку профиля сотрудника");
  }

  let verifiedEmployeeId = "";
  try {
    const verifyModel = new DynamicModel({"employeeId": ""});
    verifiedLink.unmarshalJSONField("payload", verifyModel);
    verifiedEmployeeId = String(verifyModel.employeeId || "");
  } catch (_) {
    verifiedEmployeeId = "";
  }
  if (!verifiedEmployeeId || verifiedEmployeeId !== String(body.employeeId || login)) {
    throw new InternalServerError("Серверная привязка сотрудника не прошла проверку");
  }

  return e.json(created ? 201 : 200, {
    "id": verifiedUser.id,
    "email": verifiedUser.getString("email"),
    "name": verifiedUser.getString("name"),
    "login": login,
    "employeeId": verifiedEmployeeId,
    "created": created,
    "linked": true,
    "verified": true,
  });'''
if old not in text:
    raise SystemExit('employee provision verification anchor not found')
text = text.replace(old, new, 1)
portal.write_text(text, encoding='utf-8')

# 3. Allow unlimited manual reactivation for both inactive and active employees.
contacts = Path('lib/features/team/contacts_screen.dart')
text = contacts.read_text(encoding='utf-8')
old = '''    if (!_ownerOnly ||
        employee.isOwner ||
        _activationBusy.contains(employee.id)) {
      return;
    }

    final confirmed = await showDialog<bool>('''
new = '''    if (!_ownerOnly ||
        employee.isOwner ||
        _activationBusy.contains(employee.id)) {
      return;
    }

    final alreadyActive = EmployeeAdminService.isActivated(employee.id);
    final confirmed = await showDialog<bool>('''
if old not in text:
    raise SystemExit('activation guard anchor not found')
text = text.replace(old, new, 1)
old = '''        title: Text(
          _ru ? 'Повторить активацию?' : 'Retry activation?',
          style: TextStyle('''
new = '''        title: Text(
          alreadyActive
              ? (_ru ? 'Переактивировать сотрудника?' : 'Reactivate employee?')
              : (_ru ? 'Повторить активацию?' : 'Retry activation?'),
          style: TextStyle('''
if old not in text:
    raise SystemExit('activation title anchor not found')
text = text.replace(old, new, 1)
old = '''    final canRetry = !active && !busy && (error.isNotEmpty || stalled);
    final canActivate = !active && !busy && attempted == null;
    final attemptText = attempted == null'''
new = '''    final canRetry = !active && !busy && (error.isNotEmpty || stalled);
    final canActivate = !active && !busy && attempted == null;
    final canReactivate = active && !busy;
    final attemptText = attempted == null'''
if old not in text:
    raise SystemExit('activation state anchor not found')
text = text.replace(old, new, 1)
old = '''          if (canRetry || canActivate) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor:
                    canRetry ? AppTheme.accentRed : AppTheme.accent,
              ),
              onPressed: () => _retryActivation(employee),
              icon: Icon(
                canRetry ? Icons.refresh_rounded : Icons.person_add_alt_1,
                size: 14,
              ),
              label: Text(
                canRetry
                    ? (_ru ? 'Повторить активацию' : 'Retry activation')
                    : (_ru ? 'Активировать вручную' : 'Activate manually'),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],'''
new = '''          if (canReactivate || canRetry || canActivate) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor:
                    canRetry ? AppTheme.accentRed : AppTheme.accent,
              ),
              onPressed: () => _retryActivation(employee),
              icon: Icon(
                canActivate ? Icons.person_add_alt_1 : Icons.refresh_rounded,
                size: 14,
              ),
              label: Text(
                canReactivate
                    ? (_ru ? 'Переактивировать' : 'Reactivate')
                    : canRetry
                        ? (_ru ? 'Повторить активацию' : 'Retry activation')
                        : (_ru ? 'Активировать вручную' : 'Activate manually'),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],'''
if old not in text:
    raise SystemExit('activation action anchor not found')
text = text.replace(old, new, 1)
contacts.write_text(text, encoding='utf-8')

# 4. Release version.
pubspec = Path('pubspec.yaml')
p = pubspec.read_text(encoding='utf-8')
if 'version: 0.19.15+63' not in p:
    raise SystemExit('unexpected pubspec version')
pubspec.write_text(p.replace('version: 0.19.15+63', 'version: 0.19.16+64', 1), encoding='utf-8')
appv = Path('lib/core/constants/app_version.dart')
a = appv.read_text(encoding='utf-8')
if "static const String number = '0.19.15';" not in a or 'static const int build = 63;' not in a:
    raise SystemExit('unexpected AppVersion')
a = a.replace("static const String number = '0.19.15';", "static const String number = '0.19.16';", 1)
a = a.replace('static const int build = 63;', 'static const int build = 64;', 1)
appv.write_text(a, encoding='utf-8')
PY

dart format lib/features/team/contacts_screen.dart lib/core/constants/app_version.dart
node --check server/pb_hooks/wesi_auth_bootstrap.pb.js
node --check server/pb_hooks/employee_portal.pb.js
grep -q '"employeeId": String(model.employeeId' server/pb_hooks/wesi_auth_bootstrap.pb.js
grep -q 'verifiedEmployeeId' server/pb_hooks/employee_portal.pb.js
grep -q 'Переактивировать' lib/features/team/contacts_screen.dart
grep -q '^version: 0.19.16+64$' pubspec.yaml

flutter pub get
flutter analyze --no-fatal-infos
flutter test

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add server/pb_hooks/wesi_auth_bootstrap.pb.js \
        server/pb_hooks/employee_portal.pb.js \
        lib/features/team/contacts_screen.dart \
        lib/core/constants/app_version.dart \
        pubspec.yaml pubspec.lock
git commit -m 'fix(team): verify activation and allow unlimited reactivation + 0.19.16+64'
git push origin HEAD:main

# Deploy both changed PocketBase hooks with the canonical portal deploy workflow.
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

body=''
for attempt in $(seq 1 20); do
  body=$(curl -fsS --max-time 20 https://api.wesi-inc.ru/api/wesi/auth/version || true)
  if grep -q '"version":"2026-08-09.owner-email-v10"' <<<"$body"; then break; fi
  sleep 1
done
echo "$body"
grep -q '"version":"2026-08-09.owner-email-v10"' <<<"$body"

# Build and publish Windows, Android and the Windows installer.
started=$(date -u +%s)
gh workflow run publish-wesios-production.yml \
  --repo "$GITHUB_REPOSITORY" \
  --ref main \
  -f notes='Исправлена активация сотрудников: профиль считается активированным только после серверной проверки учётной записи, пароля и привязки. Исправлен вход новых сотрудников. Для существующих сотрудников добавлена неограниченная переактивация с новым паролем.'
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
