import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('organization hierarchy v1 TZ keeps all core invariants', () {
    final text = File('TZ_ORG_HIERARCHY_V1.md').readAsStringSync();
    for (final required in <String>[
      'Финансовый факт всегда принадлежит ровно одной организации',
      'Wesi Inc → IT → Studio A',
      'Wesi Beats',
      'scope: only | subtree',
      'InterOrgTransfer',
      'ownerEmployeeId',
      'canViewTeamFinance',
      'кто ты → где ты имеешь право → что именно смотришь',
      'не должны удваивать общий cash-flow',
      'HorizonPredictionRegistry',
      'обычный сотрудник не видит чужие личные показатели',
    ]) {
      expect(text, contains(required), reason: 'Missing TZ invariant: $required');
    }
  });
}
