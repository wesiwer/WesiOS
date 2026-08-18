import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature extensions do not own run or seed history anymore', () {
    final feature =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();
    final endpoint = File('lib/core/sync/sync_endpoint.dart').readAsStringSync();

    expect(feature, isNot(contains("static const _lastRunKey")));
    expect(feature, isNot(contains("static const _seededKey")));
    expect(feature, isNot(contains('_stashMarkers')));
    expect(feature, isNot(contains('_restoreMarkers')));
    expect(feature, isNot(contains("sync_last_run")));
    expect(feature, isNot(contains("sync_seeded_at")));

    expect(endpoint, contains("static const String _lastRunKey = 'sync_last_run';"));
    expect(endpoint, contains("static const String _seededKey = 'sync_seeded_at';"));
    expect(endpoint, contains("return '\$base::\$userId';"),
        reason:
            'run/seed metadata authority must remain scoped by PocketBase auth user');
  });
}
