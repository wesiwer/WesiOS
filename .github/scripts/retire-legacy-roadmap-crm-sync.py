from pathlib import Path

root = Path('.')
p = root / 'lib/core/sync/sync_feature_extensions.dart'
s = p.read_text(encoding='utf-8')

for line in [
    "import '../../features/crm/services/crm_service.dart';\n",
    "import '../../features/roadmap/services/roadmap_service.dart';\n",
]:
    if line not in s:
        raise SystemExit('legacy import not found: ' + line.strip())
    s = s.replace(line, '', 1)

for block in [
'''      if (SyncCodec.byName('roadmap_state') == null) {
        SyncCodec.collections.add(_RoadmapStateSync());
      }
''',
'''      if (SyncCodec.byName('crm_state') == null) {
        SyncCodec.collections.add(_CrmStateSync());
      }
''',
]:
    if block not in s:
        raise SystemExit('legacy registration block not found')
    s = s.replace(block, '', 1)

for block in [
'''class _RoadmapStateSync extends _KeyedStateSync {
  @override
  String get name => 'roadmap_state';
  @override
  String get boxName => RoadmapService.boxName;
  @override
  Set<String> get keys => const {'projects_v1', 'items_v1'};
  @override
  void notifyChanged() => RoadmapService.revision.value++;
}

''',
'''class _CrmStateSync extends _KeyedStateSync {
  @override
  String get name => 'crm_state';
  @override
  String get boxName => CrmService.boxName;
  @override
  Set<String> get keys => const {'clients_v1', 'deals_v1', 'interactions_v1'};
  @override
  void notifyChanged() => CrmService.revision.value++;
}

''',
]:
    if block not in s:
        raise SystemExit('legacy class block not found')
    s = s.replace(block, '', 1)

p.write_text('\n'.join(line.rstrip() for line in s.splitlines()) + '\n', encoding='utf-8')

# Contract: new client has one canonical Roadmap/CRM representation, while
# server keeps the legacy routes for older installed clients.
t = root / 'test/sync_legacy_snapshot_retirement_test.dart'
t.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new client does not register legacy Roadmap and CRM snapshots', () {
    final extensions =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();
    expect(extensions, isNot(contains("SyncCodec.byName('roadmap_state')")));
    expect(extensions, isNot(contains('_RoadmapStateSync')));
    expect(extensions, isNot(contains("SyncCodec.byName('crm_state')")));
    expect(extensions, isNot(contains('_CrmStateSync')));
  });

  test('per-record Roadmap and CRM remain canonical in SyncCodec', () {
    final codec = File('lib/core/sync/sync_codec.dart').readAsStringSync();
    for (final required in <String>[
      'RoadmapProjectsSync()',
      'RoadmapItemsSync()',
      'CrmClientsSync()',
      'CrmDealsSync()',
      'CrmInteractionsSync()',
    ]) {
      expect(codec, contains(required), reason: 'missing $required');
    }
  });

  test('server keeps legacy Roadmap and CRM routes for old clients', () {
    final read = File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();
    final write = File('server/pb_hooks/wesi_sync_write.pb.js').readAsStringSync();
    for (final legacy in <String>['roadmap_state', 'crm_state']) {
      expect(read, contains('"$legacy": true'));
      expect(write, contains('"$legacy": true'));
    }
  });
}
''', encoding='utf-8')

print('LEGACY_ROADMAP_CRM_SYNC_RETIREMENT_READY')
