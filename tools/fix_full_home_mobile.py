from pathlib import Path
import re


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

# The real blank-Home trigger: WesiAvatar used Hive.box() directly during
# build. If the settings box was not open yet, Flutter replaced the avatar with
# an ErrorWidget. In the Home header Row that ErrorWidget exploded the layout
# to ~100k px, pushing every following sliver off-screen. Rendering an avatar
# must never depend on storage being ready.
avatar_path = Path('lib/core/widgets/wesi_avatar.dart')
avatar = avatar_path.read_text(encoding='utf-8')
pattern = re.compile(
    r"  @override\n  Widget build\(BuildContext context\) \{.*?\n  \}\n\n  /// Набор пресетов\.",
    re.S,
)
replacement = r'''  @override
  Widget build(BuildContext context) {
    Box<dynamic>? box;
    try {
      if (Hive.isBoxOpen(_box)) box = Hive.box<dynamic>(_box);
    } catch (_) {
      box = null;
    }

    // Настройки могут открываться позже первого кадра. Аватар в таком случае
    // обязан показать безопасный пресет, а не уронить всю шапку Home.
    if (box == null) return _buildAvatar(null);

    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: box.listenable(keys: const [_key, _customKey]),
      builder: (context, liveBox, _) => _buildAvatar(liveBox),
    );
  }

  Widget _buildAvatar(Box<dynamic>? box) {
    final border = showBorder
        ? Border.all(
            color: AppTheme.accent.withOpacity(0.55),
            width: size > 40 ? 2.2 : 1.5,
          )
        : null;
    final shadow = [
      BoxShadow(
        color: AppTheme.accent.withOpacity(0.12),
        blurRadius: size * 0.25,
        spreadRadius: 1,
      ),
    ];

    final custom = photo ?? (index == null ? customBytes : null);
    final Widget avatar;

    if (custom != null) {
      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          boxShadow: shadow,
          image: DecorationImage(
            image: MemoryImage(custom),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      var storedIndex = 0;
      if (box != null) {
        final raw = box.get(_key, defaultValue: 0);
        if (raw is int) storedIndex = raw;
      }
      final resolved = (index ?? storedIndex).clamp(0, avatarPresets.length - 1);
      final preset = avatarPresets[resolved];

      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: preset.gradient,
          border: border,
          boxShadow: shadow,
        ),
        child: Center(
          child: IconTheme(
            data: IconThemeData(size: size * 0.45),
            child: preset.icon,
          ),
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  /// Набор пресетов.'''
avatar, count = pattern.subn(replacement, avatar, count=1)
if count != 1:
    raise SystemExit(f'wesi_avatar.dart: build replacement count={count}')
avatar_path.write_text(avatar, encoding='utf-8')

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

# Full-screen regression test. Crucially, wesios_settings is intentionally NOT
# opened: this reproduces the startup race that made WesiAvatar destroy Home.
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

    final clock = tester.getRect(find.byKey(const ValueKey('home_clock_panel')));
    final charge = tester.getRect(find.byKey(const ValueKey('home_mind_charge')));
    final quote = tester.getRect(find.byKey(const ValueKey('home_quote_card')));

    expect(clock.width, greaterThanOrEqualTo(327));
    expect(clock.height, greaterThanOrEqualTo(160));

    // После часов реально идут остальные блоки, а не белое поле.
    expect(charge.top, greaterThanOrEqualTo(clock.bottom));
    expect(quote.top, greaterThanOrEqualTo(charge.bottom));
    expect(charge.top, lessThan(800));
    expect(quote.top, lessThan(800));
    expect(tester.takeException(), isNull);

    // Нижняя часть главной тоже существует и доступна прокруткой.
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
'''
Path('test/home_mobile_layout_test.dart').write_text(test, encoding='utf-8')

print('Full Home mobile regression fix applied')
