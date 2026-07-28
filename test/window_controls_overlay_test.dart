import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wesios/core/widgets/window_controls.dart';

/// `MaterialApp.builder` находится выше Navigator, поэтому Overlay.of()
/// оттуда не виден. Tooltip внутри WindowControls требует Overlay-предка —
/// без него подсказки на кнопках окна падают.
///
/// Тест повторяет структуру из `app.dart` и проверяет, что подсказка
/// действительно всплывает.
void main() {
  testWidgets('tooltips in the app-level overlay find an Overlay ancestor',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('content')),
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            Positioned.fill(
              child: Overlay(
                initialEntries: [
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
      ),
    );

    expect(tester.takeException(), isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // Наводимся на кнопку «Свернуть»
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.remove)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Свернуть'), findsOneWidget);
  });
}
