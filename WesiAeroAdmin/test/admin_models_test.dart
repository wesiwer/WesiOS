import 'package:flutter_test/flutter_test.dart';
import 'package:wesi_aero_admin/src/models/admin_models.dart';

void main() {
  test('parses snapshot counts and pricing', () {
    final snapshot = AdminSnapshot.fromJson({
      'revision': 9,
      'generatedAt': '2026-08-21T12:00:00Z',
      'counts': {
        'servers': 2,
        'serversOnline': 1,
        'licenses': 4,
        'licensesActive': 3,
        'devices': 5,
        'payments': 2,
        'paymentsPaid': 1,
        'revenueMinor': 34900,
      },
      'servers': <dynamic>[],
      'plans': [
        {
          'id': 'aero-flex',
          'name': 'Aero Flex',
          'pricing': {
            'shared': {
              '30': {'base': 34900, 'extraDevice': 12900},
            },
          },
        },
      ],
      'licenses': <dynamic>[],
      'payments': <dynamic>[],
      'paymentSettings': <dynamic>[],
    });
    expect(snapshot.revision, 9);
    expect(snapshot.counts.revenueMinor, 34900);
    expect(snapshot.plans.single.price('shared', 30, 'base'), 34900);
  });
}
