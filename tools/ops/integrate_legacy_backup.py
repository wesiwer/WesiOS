from pathlib import Path

# LocalBackupService: recognise official legacy JSON and canonicalise every
# restored row through today's codec before touching Hive.
p = Path('lib/core/backup/local_backup_service.dart')
s = p.read_text(encoding='utf-8')
if "import 'legacy_json_backup.dart';" not in s:
    anchor = "import 'package:hive/hive.dart';\n\n"
    if anchor not in s:
        raise SystemExit('backup import anchor not found')
    s = s.replace(anchor, anchor + "import 'legacy_json_backup.dart';\n\n", 1)

needle = "    if (envelopeRaw is! Map || envelopeRaw['format'] != format) {"
if needle not in s:
    raise SystemExit('backup format anchor not found')
if 'LegacyJsonBackup.looksLike(envelopeRaw)' not in s:
    block = """    if (LegacyJsonBackup.looksLike(envelopeRaw)) {
      try {
        final parsed = LegacyJsonBackup.parse(
          Map<dynamic, dynamic>.from(envelopeRaw as Map),
        );
        return _DecodedBackup(
          createdAt: parsed.createdAt,
          collections: parsed.collections,
          settings: const <String, dynamic>{},
        );
      } on FormatException catch (error) {
        throw LocalBackupException(
          'BACKUP_LEGACY_INVALID',
          '${error.message}',
        );
      }
    }
"""
    s = s.replace(needle, block + needle, 1)

old = """          final fields = Map<String, dynamic>.from(rawFields);
          final accepted = await collection.applyFields(fields);
"""
new = """          final fields = Map<String, dynamic>.from(rawFields);
          final decoded = collection.decode(fields);
          if (decoded == null) {
            throw LocalBackupException(
              'BACKUP_ROW_REJECTED',
              'Не удалось преобразовать ${entry.key}:$id в текущий формат WesiOS',
            );
          }
          final canonicalFields = Map<String, dynamic>.from(
            collection.encode(decoded),
          );
          final accepted = await collection.applyFields(canonicalFields);
"""
if old not in s:
    raise SystemExit('restore canonicalization anchor not found')
s = s.replace(old, new, 1)
old_verify = '_sameValue(collection.encode(restored), fields)'
if old_verify not in s:
    raise SystemExit('restore verify anchor not found')
s = s.replace(
    old_verify,
    '_sameValue(collection.encode(restored), canonicalFields)',
    1,
)
p.write_text(s, encoding='utf-8')

# Sync UI: current .wesibackup plus the original human-readable JSON v1.
p = Path('lib/features/settings/sync_screen.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    "allowedExtensions: const <String>['wesibackup'],",
    "allowedExtensions: const <String>['wesibackup', 'json'],",
    1,
)
old = ('Выберите файл .wesibackup, созданный кнопкой экспорта резервной копии. '
       'Служебный JSON восстановить здесь нельзя.')
new = ('Выберите резервную копию WesiOS: новый файл .wesibackup или старый '
       'JSON-файл экспорта WesiOS.')
if old not in s:
    raise SystemExit('legacy picker message anchor not found')
s = s.replace(old, new, 1)
s = s.replace(
    'Choose a .wesibackup file created by Backup export. Internal JSON files cannot be restored here.',
    'Choose a WesiOS backup: a current .wesibackup file or a legacy WesiOS JSON export.',
    1,
)
p.write_text(s, encoding='utf-8')

# Rescue release version must match pubspec.yaml 0.22.35+110.
p = Path('lib/core/constants/app_version.dart')
s = p.read_text(encoding='utf-8')
s = s.replace("static const String number = '0.22.34';", "static const String number = '0.22.35';")
s = s.replace('static const int build = 109;', 'static const int build = 110;')
p.write_text(s, encoding='utf-8')
