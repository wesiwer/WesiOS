import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server normalizes legacy organization payloads for strict clients', () {
    final source = File('server/pb_hooks/wesi_sync_read.pb.js').readAsStringSync();

    expect(source, contains('const normalizeOrganizationPayload ='));
    expect(source, contains('if (!p.createdAt) p.createdAt = String(p.created ||'));
    expect(source, contains('if (!p.updatedAt) p.updatedAt = String(p.updated ||'));
    expect(source, contains('if (id === "org_wesi_inc")'));
    expect(source, contains('p.isRoot = true;'));
    expect(source, contains('p.parentId = null;'));
    expect(source, contains('p.isRoot = false;'));
    expect(source, contains('p = normalizeOrganizationPayload(p, row);'));
  });

  test('obsolete Telegram planned tile is absent from settings', () {
    final source = File('lib/features/settings/settings_screen.dart').readAsStringSync();

    expect(source, isNot(contains("title: WesiLocale.get('telegram_bot')")));
    expect(source, isNot(contains('icon: Icons.telegram')));
  });
}
