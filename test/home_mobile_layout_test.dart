import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/widgets/wesi_clock.dart';
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

    // wesios_settings специально не открываем. Раньше WesiAvatar падал здесь
    // с HiveError, раздувал верхний Row до ~100000 px и скрывал всю ленту.
    expect(Hive.isBoxOpen('wesios_settings'), isFalse);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(WesiWordmark), findsOneWidget);
    expect(find.byType(WesiClock), findsOneWidget);
    expect(find.byKey(const ValueKey('home_clock_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_mind_charge')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_quote_card')), findsOneWidget);

    final clock =
        tester.getRect(find.byKey(const ValueKey('home_clock_panel')));
    final charge =
        tester.getRect(find.byKey(const ValueKey('home_mind_charge')));
    final quote = tester.getRect(find.byKey(const ValueKey('home_quote_card')));

    expect(clock.width, greaterThanOrEqualTo(327));
    expect(clock.height, greaterThanOrEqualTo(160));

    // После часов реально идут остальные блоки, а не белое поле.
    expect(charge.top, greaterThanOrEqualTo(clock.bottom));
    expect(quote.top, greaterThanOrEqualTo(charge.bottom));
    expect(charge.top, lessThan(800));
    expect(quote.top, lessThan(800));
    expect(tester.takeException(), isNull);

    // Нижняя часть главной тоже существует и доступна прокруткой. Этот шаг
    // отдельно защищает узкие GlassCard-заголовки/действия от RenderFlex
    // overflow на реальной Android-ширине 360 px после асинхронной подгрузки.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('home_balance_card')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('home_balance_card'))).top,
      lessThan(800),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
