import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('0.22.30 rollout keeps organization compatibility and Telegram cleanup', () {
    final sync = File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();
    final settings = File('lib/features/settings/settings_screen.dart').readAsStringSync();

    expect(sync, contains('normalizeOrganizationPayload'));
    expect(sync, contains('if (id === "org_wesi_inc")'));
    expect(settings, isNot(contains("icon: Icons.telegram")));
  });
}
