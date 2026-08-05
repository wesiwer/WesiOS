import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/theme/app_theme.dart';
import 'package:wesios/core/widgets/wesi_clock.dart';
import 'package:wesios/core/widgets/wesi_quote_card.dart';

/// Шапка главной: часы с месяцем и карточка цитаты.
///
/// Оба виджета стоят в дереве под `const` и своих причин перестроиться не
/// имеют — именно поэтому цитата и застревала в цветах прошлой темы.
void main() {
  Widget host(Widget child, {double width = 230}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  /// Часы держат таймер на секунду. Без размонтирования тест падает на
  /// «остался незавершённый таймер», причём в следующем тесте.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  group('месяц рядом с часами', () {
    testWidgets('показывает все дни текущего месяца', (tester) async {
      await tester.pumpWidget(host(const WesiClock(showSeconds: false)));

      final today = DateTime.now();
      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

      for (final day in [1, 15, daysInMonth]) {
        expect(find.text('$day'), findsOneWidget, reason: 'день $day');
      }
      if (daysInMonth < 31) {
        expect(find.text('31'), findsNothing);
      }

      await unmount(tester);
    });

    testWidgets('сегодняшнее число подсвечено', (tester) async {
      await tester.pumpWidget(host(const WesiClock(showSeconds: false)));

      final day = DateTime.now().day;
      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('$day'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((pill.decoration! as BoxDecoration).color, AppTheme.accent);

      await unmount(tester);
    });

    testWidgets('умещается в узкую колонку шапки', (tester) async {
      // 190 px — левая колонка на самом узком телефоне, который мы
      // поддерживаем.
      await tester.pumpWidget(host(const WesiClock(), width: 190));
      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('цитата', () {
    testWidgets('перекрашивается сразу при смене темы', (tester) async {
      ThemeNotifier.instance.setDark();
      await tester.pumpWidget(host(const WesiQuoteCard(), width: 360));

      LinearGradient gradient() => (tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
              .decoration! as BoxDecoration)
          .gradient! as LinearGradient;

      final dark = gradient().colors.first;

      ThemeNotifier.instance.setLight();
      await tester.pump();

      final light = gradient().colors.first;

      // Цвет обязан смениться без перезахода на экран: раньше карточка
      // оставалась оранжевой на светлой теме и синей на тёмной.
      expect(light, isNot(dark));
      expect(light.value, AppTheme.accent.withOpacity(0.10).value);

      ThemeNotifier.instance.setDark();
      await unmount(tester);
    });
  });
}
