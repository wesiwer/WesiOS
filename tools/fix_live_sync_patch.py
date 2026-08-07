from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Patch anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/core/sync/sync_auto.dart',
    "import 'sync_journal.dart';\n",
    "import 'sync_journal.dart';\nimport 'sync_transport.dart';\n",
)
replace_once(
    'lib/core/sync/sync_auto.dart',
    "    _probeFailures = (_probeFailures + 1).clamp(1, 6);\n    final seconds = 1 << _probeFailures; // 2, 4, 8, 16, 32, 64\n",
    "    _probeFailures = (_probeFailures + 1).clamp(1, 4).toInt();\n"
    "    final seconds = 1 << _probeFailures; // 2, 4, 8, 16\n",
)

# Один общий HttpClient сохраняет keep-alive соединение. Иначе revision-poll
# создавал бы новый TLS-сеанс каждую секунду на каждом устройстве.
replace_once(
    'lib/core/sync/pocketbase_transport.dart',
    "  static const int pageSize = 500;\n\n  final String baseUrl;\n",
    "  static const int pageSize = 500;\n\n"
    "  static final HttpClient _http = HttpClient()\n"
    "    ..connectionTimeout = const Duration(seconds: 12)\n"
    "    ..idleTimeout = const Duration(seconds: 30);\n\n"
    "  final String baseUrl;\n",
)
replace_once(
    'lib/core/sync/pocketbase_transport.dart',
    "    final client = HttpClient()\n      ..connectionTimeout = const Duration(seconds: 12);\n    try {\n      final req = await client.openUrl(method, uri);\n",
    "    try {\n      final req = await _http.openUrl(method, uri);\n",
)
replace_once(
    'lib/core/sync/pocketbase_transport.dart',
    "    } catch (_) {\n      return const SyncResult.fail(SyncFailure.offline);\n    } finally {\n      client.close();\n    }\n",
    "    } catch (_) {\n      return const SyncResult.fail(SyncFailure.offline);\n    }\n",
)

# Ручная кнопка должна дождаться уже идущего auto-sync, а не молча ничего
# не сделать. SyncAuto.now() сам ждёт busy до двух секунд.
replace_once(
    'lib/features/home/home_screen.dart',
    "    if (_syncing || SyncEngine.busy.value) return;\n",
    "    if (_syncing) return;\n",
)

print('Live sync follow-up fixes applied successfully')
