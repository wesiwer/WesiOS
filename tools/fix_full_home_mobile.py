from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected one anchor, got {text.count(old)}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# WesiClock used to rely on its children to determine the sliver footprint.
# A painted calendar could therefore look present while the Home header itself
# occupied an invalid/tiny layout area. Give the clock a deterministic mobile
# footprint: what is painted is also what the scroll view reserves.
replace_once(
    'lib/core/widgets/wesi_clock.dart',
    """          return _buildClockBody(math.max(160.0, available), available >= 300);""",
    """          final width = math.max(160.0, available);
          final large = width >= 300;
          return SizedBox(
            width: width,
            height: large ? 168 : 116,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildClockBody(width, large),
            ),
          );""",
)

# Mark the critical Home blocks and keep them as independent, ordered slivers.
replace_once(
    'lib/features/home/home_screen.dart',
    """                        child: const SizedBox(
                          width: double.infinity,
                          child: WesiClock(),
                        ),""",
    """                        child: const SizedBox(
                          key: ValueKey('home_clock_panel'),
                          width: double.infinity,
                          child: WesiClock(),
                        ),""",
)
replace_once(
    'lib/features/home/home_screen.dart',
    """                child: QuoteMindCharge(),""",
    """                child: QuoteMindCharge(
                  key: ValueKey('home_mind_charge'),
                ),""",
)
replace_once(
    'lib/features/home/home_screen.dart',
    """                child: WesiQuoteCard(),""",
    """                child: WesiQuoteCard(
                  key: ValueKey('home_quote_card'),
                ),""",
)
replace_once(
    'lib/features/home/home_screen.dart',
    """                child: GlassCard(
                  child: Column(""",
    """                child: GlassCard(
                  key: const ValueKey('home_balance_card'),
                  child: Column(""",
)

# Full-screen regression test. This is deliberately not another isolated clock
# test: it pumps the actual HomeScreen on a 360x800 phone and verifies that the
# rest of the feed exists, is ordered below the clock, and remains reachable.
test = r'''import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/widgets/quote_mind_charge.dart';
import 'package:wesios/core/widgets/wesi_clock.dart';
import 'package:wesios/core/widgets/wesi_quote_card.dart';
import 'package:wesios/core/widgets/wesi_wordmark.dart';
import 'package:wesios/features/home/home_screen.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDir = await Directory.systemTemp.createTemp('wesios_home_mobile_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TransactionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TransactionTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(RecurringPeriodAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  testWidgets('главная на телефоне не превращается в пустой экран',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(WesiWordmark), findsOneWidget);
    expect(find.byType(WesiClock), findsOneWidget);
    expect(find.byKey(const ValueKey('home_clock_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_mind_charge')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_quote_card')), findsOneWidget);

    final clock = tester.getRect(find.byKey(const ValueKey('home_clock_panel')));
    final charge = tester.getRect(find.byKey(const ValueKey('home_mind_charge')));
    final quote = tester.getRect(find.byKey(const ValueKey('home_quote_card')));

    // 360 - 16 - 16 = 328. Часы должны занимать реальную ширину контента,
    // а не старую узкую колонку ~190 px.
    expect(clock.width, greaterThanOrEqualTo(327));
    expect(clock.height, greaterThanOrEqualTo(160));

    // Главное условие регресса с фотографии: после часов действительно идут
    // остальные блоки, а не белое поле.
    expect(charge.top, greaterThanOrEqualTo(clock.bottom));
    expect(quote.top, greaterThanOrEqualTo(charge.bottom));
    expect(charge.top, lessThan(800));
    expect(quote.top, lessThan(800));
    expect(tester.takeException(), isNull);

    // И нижняя часть главной тоже существует и доступна прокруткой.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('home_balance_card')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('home_balance_card'))).top,
      lessThan(800),
    );
    expect(tester.takeException(), isNull);

    // Снимаем экран, чтобы секундный Timer WesiClock не оставался в тесте.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
'''
Path('test/home_mobile_layout_test.dart').write_text(test, encoding='utf-8')

print('Full Home mobile regression fix applied')
