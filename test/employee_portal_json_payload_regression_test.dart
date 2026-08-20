import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee bootstrap decodes PocketBase JSON payload after valid OTP', () {
    final source = File('server/pb_hooks/employee_portal.pb.js').readAsStringSync();

    final unmarshal = source.indexOf('record.unmarshalJSONField(field, model);');
    final rawRead = source.indexOf('const raw = record.get(field);');

    expect(unmarshal, greaterThanOrEqualTo(0));
    expect(
      rawRead,
      greaterThan(unmarshal),
      reason: 'PocketBase typed JSON decoding must be attempted before raw fallback',
    );
    expect(source.contains('"employeeId": model.employeeId'), isTrue);
    expect(source.contains('"snapshot": model.snapshot'), isTrue);
    expect(
      source.contains('typeof raw === "object" && typeof raw.get === "function"'),
      isTrue,
    );
    expect(
      source.contains('return value && typeof value === "object" ? value : {};'),
      isFalse,
      reason: 'plain-object assumption breaks portal-account JSON values after OTP',
    );
  });
}
