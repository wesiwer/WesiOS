import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server rejects tombstones for durable business collections', () {
    final source =
        File('server/pb_hooks/wesi_sync_write.pb.js').readAsStringSync();

    final deleted = source.indexOf('const deleted = body.deleted === true;');
    final atomic = source.indexOf('wesi_sync_atomic.js');
    expect(deleted, greaterThanOrEqualTo(0));
    expect(atomic, greaterThan(deleted),
        reason: 'authoritative writes must pass through the atomic boundary');

    final guard = source.indexOf('if (deleted && (', deleted);
    expect(guard, greaterThan(deleted));
    expect(guard, lessThan(atomic),
        reason:
            'incompatible tombstones must fail before the authoritative atomic save');

    for (final collection in <String>[
      'organizations',
      'accounts',
      'inter_org_transfers',
    ]) {
      expect(
        source.substring(guard, atomic),
        contains('collection === "$collection"'),
        reason: '$collection is durable and its client codec does not delete it',
      );
    }
  });

  test('client verifies tombstone actually left the sync projection', () {
    final source = File('lib/core/sync/sync_engine.dart').readAsStringSync();
    expect(
      source,
      contains('accepted = _localValueBySyncId(c, r.id) == null;'),
      reason:
          'removeById returning normally is not proof that a durable row was deleted',
    );
  });
}
