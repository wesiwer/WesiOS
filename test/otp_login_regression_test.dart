import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OTP verify cannot be submitted twice while a request is in flight', () {
    final source =
        File('lib/features/auth/login_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _verifyCode() async {');
    expect(start, isNonNegative);
    final end = start + 220 < source.length ? start + 220 : source.length;
    final window = source.substring(start, end);
    expect(window, contains('if (_busy) return;'));
  });

  test('dead OTP challenge returns to a fresh sign-in flow', () {
    final source =
        File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(source, contains('bool _challengeEnded(PortalLoginResult result)'));
    expect(source, contains("message.contains('уже использован')"));
    expect(source, contains('_challengeId = null;'));
  });

  test('new start-v2 OTP invalidates older pending OTPs', () {
    final source =
        File('server/pb_hooks/wesi_auth_bootstrap.pb.js').readAsStringSync();
    expect(source,
        contains('Only the newest successfully delivered OTP remains usable'));
    expect(source, contains('item.set("deleted", true);'));
    expect(source, contains('2026-08-09.owner-email-v11'));
  });

  test(
      'legacy security login reads employeeId and dead challenges are explicit',
      () {
    final source =
        File('server/pb_hooks/wesi_security.pb.js').readAsStringSync();
    expect(source, contains('"employeeId": String(model.employeeId || "")'));
    expect(source, contains('Код уже использован. Запросите новый код'));
    expect(source, contains('2026-08-09.security-mail-v9'));
  });
}
