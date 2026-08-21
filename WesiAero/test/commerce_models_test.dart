import 'package:flutter_test/flutter_test.dart';
import 'package:wesi_aero/src/models/commerce_models.dart';

void main() {
  test('calculates the same price formula as the control plane', () {
    final plan = TariffPlan.fromJson({
      'id': 'aero-flex',
      'name': 'Aero Flex',
      'currency': 'RUB',
      'pricing': {
        'shared': {
          for (final days in [7, 30, 90, 180, 365])
            '$days': {'base': 34900, 'extraDevice': 12900},
        },
        'dedicated': {
          for (final days in [7, 30, 90, 180, 365])
            '$days': {'base': 79900, 'extraDevice': 17900},
        },
      },
    });
    expect(plan.amountFor(AeroIpMode.shared, 3, 30), 60700);
    expect(plan.amountFor(AeroIpMode.dedicated, 2, 30), 97800);
  });
}
