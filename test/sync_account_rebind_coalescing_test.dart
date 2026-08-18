import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account changes that arrive during rebind are queued, not discarded', () {
    final source =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

    final listenerStart = source.indexOf('static void _onTeamRevision()');
    final requestStart = source.indexOf('static void _requestRebind()');
    expect(listenerStart, greaterThanOrEqualTo(0));
    expect(requestStart, greaterThan(listenerStart));

    final listener = source.substring(listenerStart, requestStart);
    expect(listener, isNot(contains('if (_rebinding ||')),
        reason:
            'identity changes must not be dropped merely because an old rebind is active');
    expect(listener, contains('_requestRebind();'));
    expect(source, contains('_rebindRequestGeneration++'));
    expect(source, contains('while (true)'));
    expect(
      source,
      contains('handledGeneration == _rebindRequestGeneration'),
      reason: 'the worker must drain changes that arrived across await points',
    );
  });

  test('stale rebind pass cannot start auto sync for a different employee', () {
    final source =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

    expect(source, contains('final targetEmployeeId = TeamService.current?.id;'));
    expect(
      source,
      contains('if (TeamService.current?.id != targetEmployeeId) return;'),
      reason: 'identity must be revalidated after SyncEngine.reset()',
    );
    expect(
      source,
      contains('_boundEmployeeId != targetEmployeeId'),
      reason: 'private binding must still match before full sync starts',
    );

    final startAuto = source.lastIndexOf('SyncAuto.start();');
    final finalIdentityCheck = source.lastIndexOf(
      'TeamService.current?.id == targetEmployeeId',
      startAuto,
    );
    expect(startAuto, greaterThanOrEqualTo(0));
    expect(finalIdentityCheck, greaterThanOrEqualTo(0));
    expect(finalIdentityCheck, lessThan(startAuto),
        reason:
            'auto sync may only be enabled after a final current-account check');
  });
}
