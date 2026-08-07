from pathlib import Path

path = Path('.github/workflows/repair-android-signature.yml')
text = path.read_text(encoding='utf-8')
old = """          $SSH \"$USER@$HOST\" \\
            \"WESI_ARTIFACTS='${ARTIFACTS_DIR:-/opt/pocketbase/pb_public/artifacts}' \\
             bash '$REMOTE_TMP/deploy-artifact.sh' \\
             --version '$VERSION' --build '$BUILD' --from '$REMOTE_TMP' \\
             --notes 'CRM, Roadmap и Wesi Console. Подписанная Android-сборка.'\"\n\n      - name: Verify published manifest and files\n"""
new = """          RELEASE_ROOT=\"${ARTIFACTS_DIR:-/srv/wesi-artifacts}\"\n          # /srv/wesi-artifacts — текущий production-root и для портала, и для\n          # релизов. Не откатываемся молча на legacy /opt: иначе deploy пишет\n          # новый manifest в одно место, а публичный /artifacts читает другое.\n          $SSH \"$USER@$HOST\" \\
            \"WESI_ARTIFACTS='$RELEASE_ROOT' \\
             bash '$REMOTE_TMP/deploy-artifact.sh' \\
             --version '$VERSION' --build '$BUILD' --from '$REMOTE_TMP' \\
             --notes 'CRM, Roadmap и Wesi Console. Подписанная Android-сборка.'\"\n\n          # Сначала проверяем ровно тот manifest, который только что записали\n          # на сервере. Так сразу видно, проблема в публикации или в HTTP-route.\n          $SSH \"$USER@$HOST\" \\
            \"python3 - '$RELEASE_ROOT/app/app-manifest.json' '$VERSION' '$BUILD' <<'PY'\nimport json, sys\npath, version, build = sys.argv[1], sys.argv[2], int(sys.argv[3])\nwith open(path, encoding='utf-8') as f:\n    manifest = json.load(f)\nassert manifest['version'] == version, (manifest.get('version'), version)\nassert int(manifest['build']) == build, (manifest.get('build'), build)\nfor platform in ('android', 'windows'):\n    entry = manifest[platform]\n    assert int(entry['sizeBytes']) > 0\n    assert len(entry['sha256']) == 64\nprint('server manifest OK:', version, build)\nPY\"\n\n      - name: Verify published manifest and files\n"""
if old not in text:
    raise SystemExit('release publish anchor not found')
text = text.replace(old, new, 1)

old2 = """          curl --retry 4 --retry-all-errors -fsS --max-time 30 \\
            \"$BASE/app/app-manifest.json?run=$GITHUB_RUN_ID\" -o app-manifest.json\n          BASE=\"$BASE\" python3 <<'PY'\n"""
new2 = """          curl --retry 4 --retry-all-errors -fsS --max-time 30 \\
            -H 'Accept: application/json' \\
            \"$BASE/app/app-manifest.json?run=$GITHUB_RUN_ID\" -o app-manifest.json\n          test -s app-manifest.json || { echo \"::error::Публичный app-manifest.json пуст\"; exit 1; }\n          python3 -m json.tool app-manifest.json >/dev/null || {\n            echo \"::error::Публичный /artifacts отдаёт не JSON. Первые 300 байт:\"\n            head -c 300 app-manifest.json || true\n            echo\n            exit 1\n          }\n          BASE=\"$BASE\" python3 <<'PY'\n"""
if old2 not in text:
    raise SystemExit('manifest verify anchor not found')
text = text.replace(old2, new2, 1)
path.write_text(text, encoding='utf-8')
print('release artifact root patch applied')
