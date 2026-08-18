import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retired aggregate/private collections cannot return to active codecs', () {
    final core = File('lib/core/sync/sync_codec.dart').readAsStringSync();
    final roadmap =
        File('lib/core/sync/sync_codec_roadmap.dart').readAsStringSync();
    final crm = File('lib/core/sync/sync_codec_crm.dart').readAsStringSync();
    final feature =
        File('lib/core/sync/sync_feature_extensions.dart').readAsStringSync();

    final activeList = core.substring(core.indexOf(
      'static final List<SyncCollection<dynamic>> collections = [',
    ));

    expect(activeList, isNot(contains("name => 'roadmap_state'")));
    expect(activeList, isNot(contains("name => 'crm_state'")));
    expect(activeList, isNot(contains("name => 'profile_private'")));

    expect(roadmap, contains("name => 'roadmap_projects'"));
    expect(roadmap, contains("name => 'roadmap_items'"));
    expect(roadmap, isNot(contains("name => 'roadmap_state'")));

    expect(crm, contains("name => 'crm_clients'"));
    expect(crm, contains("name => 'crm_deals'"));
    expect(crm, contains("name => 'crm_interactions'"));
    expect(crm, isNot(contains("name => 'crm_state'")));

    expect(feature, contains("name => 'shield_private'"));
    expect(feature, isNot(contains("name => 'profile_private'")));
  });
}
