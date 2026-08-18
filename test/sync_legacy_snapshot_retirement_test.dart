import 'dart:io';

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

  test('server keeps legacy reads for migration but refuses legacy writes', () {
    final read =
        File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();
    final write =
        File('server/pb_hooks/wesi_sync_write.pb.js').readAsStringSync();

    for (final legacy in <String>['roadmap_state', 'crm_state']) {
      expect(read, contains('"$legacy": true'),
          reason: 'legacy GET remains available for migration/diagnostics');
      expect(write, contains('"$legacy": true'),
          reason: 'the route still recognizes old clients to return a clear error');
    }

    final guard = write.indexOf(
      'if (collection === "roadmap_state" || collection === "crm_state")',
    );
    final bodyRead = write.indexOf('const body = e.requestInfo().body || {};');
    expect(guard, greaterThanOrEqualTo(0));
    expect(bodyRead, greaterThan(guard),
        reason:
            'deprecated snapshot writes must be rejected before payload parsing or mutation');
    expect(
      write,
      contains('Обновите приложение перед синхронизацией'),
      reason: 'old clients must receive an explicit upgrade-required message',
    );
  });
}
