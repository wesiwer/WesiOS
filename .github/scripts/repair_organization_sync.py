from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


codec_path = Path("lib/core/sync/sync_codec.dart")
source = codec_path.read_text(encoding="utf-8")
start = source.index("class OrganizationsSync")
end = source.index("class EmployeesSync", start)
section = source[start:end]

section = replace_once(
    section,
    "    final createdAt = _date(fields['createdAt']);",
    "\n".join(
        [
            "    // Legacy PocketBase callbacks used created/updated and could send",
            "    // stale root metadata. The immutable root id is authoritative.",
            "    final createdAt =",
            "        _date(fields['createdAt']) ??",
            "        _date(fields['created']) ??",
            "        _date(fields['updatedAt']) ??",
            "        _date(fields['updated']);",
        ]
    ),
    "organization createdAt",
)

section = replace_once(
    section,
    "\n".join(
        [
            "    final isRoot = fields['isRoot'] == true;",
            "    final parentId = _strOrNull(fields['parentId']);",
            "    if (isRoot != (id == OrganizationModel.rootId)) return null;",
            "    if (isRoot && parentId != null) return null;",
        ]
    ),
    "\n".join(
        [
            "    final canonicalRoot = id == OrganizationModel.rootId;",
            "    // A non-root row may never elevate itself. The canonical root,",
            "    // however, is repaired locally even if a stale server callback",
            "    // still sends isRoot=false or an obsolete parentId.",
            "    if (!canonicalRoot && fields['isRoot'] == true) return null;",
            "    final isRoot = canonicalRoot;",
            "    final parentId = isRoot",
            "        ? null",
            "        : (_strOrNull(fields['parentId']) ?? _strOrNull(fields['parent']));",
        ]
    ),
    "organization root metadata",
)

section = replace_once(
    section,
    "\n".join(
        [
            "    final b = box();",
            "    final incoming = decode(fields);",
            "    if (b == null || incoming == null) return false;",
        ]
    ),
    "\n".join(
        [
            "    // A lifecycle transition must not turn a closed Hive box into a",
            "    // fake REMOTE_APPLY_INCOMPLETE data error.",
            "    final b = box() ?? await ensureBox();",
            "    final incoming = decode(fields);",
            "    if (incoming == null) return false;",
        ]
    ),
    "organization applyFields",
)

codec_path.write_text(source[:start] + section + source[end:], encoding="utf-8")

test_path = Path("test/core/sync/organization_sync_legacy_root_test.dart")
test_path.write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

void main() {
  late Directory tempDir;
  late OrganizationsSync sync;

  Map<String, dynamic> payload({
    required String id,
    required String name,
    String? parentId,
    bool isRoot = false,
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'isRoot': isRoot,
    'baseCurrency': 'RUB',
    'status': 'active',
    'createdAt': '2026-08-17T13:19:24.672',
    'updatedAt': '2026-08-17T13:19:24.672',
    'createdBy': 'sync-test',
    'sortOrder': 0,
  };

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_org_legacy_sync_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(80)) {
      Hive.registerAdapter(OrganizationStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(81)) {
      Hive.registerAdapter(OrganizationModelAdapter());
    }
  });

  setUp(() async {
    sync = OrganizationsSync();
    final box = await sync.ensureBox();
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('legacy root metadata is canonicalized by immutable root id', () async {
    final legacyRoot = payload(
      id: OrganizationModel.rootId,
      name: 'Wesi Inc',
      parentId: 'legacy-parent-that-must-be-ignored',
      isRoot: false,
    )
      ..remove('createdAt')
      ..['created'] = '2026-08-17T13:19:24.672';

    expect(await sync.applyFields(legacyRoot), isTrue);

    final root = Hive.box<OrganizationModel>(
      OrganizationService.boxName,
    ).get(OrganizationModel.rootId);
    expect(root, isNotNull);
    expect(root!.isRoot, isTrue);
    expect(root.parentId, isNull);

    expect(
      await sync.applyFields(
        payload(
          id: OrganizationModel.wesiBeatsId,
          name: 'Wesi Beats',
          parentId: OrganizationModel.rootId,
        ),
      ),
      isTrue,
    );
  });

  test('organization apply reopens a closed Hive box', () async {
    final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
    await box.close();

    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc'),
      ),
      isTrue,
    );
    expect(Hive.isBoxOpen(OrganizationService.boxName), isTrue);
  });
}
""",
    encoding="utf-8",
)

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text(encoding="utf-8")
pub = replace_once(pub, "version: 0.22.32+107", "version: 0.22.33+108", "pubspec version")
pubspec.write_text(pub, encoding="utf-8")

app_version = Path("lib/core/constants/app_version.dart")
version_source = app_version.read_text(encoding="utf-8")
version_source = replace_once(
    version_source,
    "static const String number = '0.22.32';",
    "static const String number = '0.22.33';",
    "AppVersion number",
)
version_source = replace_once(
    version_source,
    "static const int build = 107;",
    "static const int build = 108;",
    "AppVersion build",
)
app_version.write_text(version_source, encoding="utf-8")
