import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/constants/app_version.dart';

void main() {
  test('AppVersion matches pubspec.yaml exactly', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^+\s]+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must contain version x.y.z+build');
    expect(AppVersion.number, match!.group(1));
    expect(AppVersion.build, int.parse(match.group(2)!));
  });
}
