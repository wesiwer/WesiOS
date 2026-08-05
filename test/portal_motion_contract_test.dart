import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portal keeps auth at bottom and uses one flexible runner', () {
    final html = File('server/employee-portal/index.html').readAsStringSync();
    final motion = File('server/employee-portal/motion-v6.js').readAsStringSync();
    final css = File('server/employee-portal/portal-v6.css').readAsStringSync();

    expect(html, contains('id="authorization"'));
    expect(html.indexOf('id="authorization"'), greaterThan(html.indexOf('id="motionRail"')));
    expect(html, contains('runnerSvg'));
    expect(html, isNot(contains('для сотрудников')));
    expect(motion, contains('catmullRom'));
    expect(motion, contains('requestAnimationFrame'));
    expect(css, contains('.brand-copy strong em'));
  });
}
