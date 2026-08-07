from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

replace_once(
    'lib/features/home/home_screen.dart',
    "import '../../core/sync/sync_auto.dart';\nimport '../../core/sync/sync_engine.dart';\n",
    "import '../../core/sync/sync_auto.dart';\n",
)

replace_once(
    'lib/core/sync/sync_auto.dart',
    "        final report = await _runAuto();\n        if (report.ok) _remoteRevision = revision;\n        return;\n",
    "        final report = await _runAuto();\n        if (report.ok) {\n          _remoteRevision = revision;\n        } else {\n          _registerProbeFailure();\n        }\n        return;\n",
)

replace_once(
    'lib/core/sync/sync_auto.dart',
    "      final report = await _runAuto();\n      if (report.ok) {\n        await _captureRemoteRevision(fallback: revision);\n      }\n",
    "      final report = await _runAuto();\n      if (report.ok) {\n        await _captureRemoteRevision(fallback: revision);\n      } else {\n        _registerProbeFailure();\n      }\n",
)

print('CI/live-sync retry fixes applied')
