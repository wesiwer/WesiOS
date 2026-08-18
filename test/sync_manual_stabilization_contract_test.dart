import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual sync retries optimistic local conflicts before surfacing failure',
      () {
    final source = File('lib/core/sync/sync_auto.dart').readAsStringSync();
    final manual = source.substring(source.indexOf('static Future<SyncReport> now()'));

    expect(manual, contains("code == 'LOCAL_CHANGED_DURING_SYNC'"));
    expect(manual, contains('await Future<void>.delayed(quiet);'));
    expect(manual, contains("lastRetryReason = code == 'BUSY' ? 'busy' : 'local';"));
    expect(manual, contains("'LOCAL_UNSTABLE'"));
    expect(manual, contains("'REMOTE_UNSTABLE'"));

    final run = manual.indexOf('final report = await SyncEngine.run();');
    final immediateReturn = manual.indexOf('if (!report.ok) return report;');
    expect(run, greaterThanOrEqualTo(0));
    expect(immediateReturn, -1,
        reason:
            'LOCAL_CHANGED_DURING_SYNC is an expected optimistic retry, not an immediate manual failure');
  });
}
