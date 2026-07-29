import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wesios/core/security/shield_lock_screen.dart';
import 'package:wesios/core/security/shield_service.dart';
import 'package:wesios/core/widgets/window_controls.dart';

/// Замок Wesi Shield живёт в том же Overlay, что калькулятор и кнопки окна.
/// Порядок записей там — не косметика: если поставить замок выше кнопок окна,
/// заблокированное приложение нельзя будет ни свернуть, ни закрыть.
///
/// Тест повторяет структуру из `app.dart` и проверяет обе стороны: содержимое
/// приложения замок перекрывает, кнопки окна — нет.
void main() {
  Widget appLike() => MaterialApp(
        home: const Scaffold(body: Center(child: Text('содержимое'))),
        builder: (context, child) => Stack(
          children: [
            if (child != null) ShieldGate(child: child),
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const ShieldOverlay()),
                  OverlayEntry(
                    builder: (_) => const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: WindowControls(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  tearDown(() {
    ShieldService.locked.value = false;
  });

  testWidgets('в разблокированном состоянии замка нет и он ничему не мешает',
      (tester) async {
    ShieldService.locked.value = false;
    await tester.pumpWidget(appLike());

    expect(find.byType(ShieldLockScreen), findsNothing);
    expect(find.text('содержимое'), findsOneWidget);

    // Пустая запись Overlay растягивается на весь экран, поэтому важно, что
    // она не перехватывает касания по содержимому под ней.
    final content = tester.renderObject(find.text('содержимое'));
    final hit = tester.hitTestOnBinding(tester.getCenter(find.text('содержимое')));
    expect(hit.path.map((e) => e.target), contains(content));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('заблокированный замок перекрывает содержимое приложения',
      (tester) async {
    await tester.pumpWidget(appLike());
    ShieldService.locked.value = true;
    await tester.pump();

    expect(find.byType(ShieldLockScreen), findsOneWidget);

    // Центр экрана занят замком: до текста под ним касание не доходит.
    final content = tester.renderObject(find.text('содержимое'));
    final hit = tester.hitTestOnBinding(tester.getCenter(find.byType(ShieldLockScreen)));
    expect(hit.path.map((e) => e.target), isNot(contains(content)));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('кнопки окна остаются нажимаемыми поверх замка', (tester) async {
    await tester.pumpWidget(appLike());
    ShieldService.locked.value = true;
    await tester.pump();

    final controls = tester.renderObject(find.byType(WindowControls));
    final hit =
        tester.hitTestOnBinding(tester.getCenter(find.byIcon(Icons.remove)));

    expect(hit.path.map((e) => e.target), contains(controls));

    await tester.pumpWidget(const SizedBox());
  });
}
