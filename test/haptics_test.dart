import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/feedback/wesi_feedback.dart';
import 'package:wesios/core/feedback/wesi_haptics.dart';

/// Точный тактильный отклик.
///
/// Сам рисунок вибрации проверить нечем — он собирается на стороне Android и
/// ощущается пальцем. Проверяется то, что ломается молча: спросили ли
/// возможности, ушло ли событие своим именем и не превратился ли отказ
/// платформы в исключение посреди нажатия.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  late TestDefaultBinaryMessenger messenger;

  void answer(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(WesiHaptics.channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    WesiHaptics.reset();
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(WesiHaptics.channel, null);
    WesiHaptics.reset();
    WesiFeedback.reset();
  });

  group('возможности устройства', () {
    test('точный отклик распознаётся', () async {
      answer((_) async => {'precise': true, 'hasVibrator': true});
      await WesiHaptics.warmUp();

      expect(WesiHaptics.precise, isTrue);
      expect(WesiHaptics.hasVibrator, isTrue);
    });

    test('простой мотор не выдаётся за точный', () async {
      // На эксцентрике рисунка не будет никогда, и настройки обязаны
      // говорить об этом прямо, а не обещать «как на айфоне».
      answer((_) async => {'precise': false, 'hasVibrator': true});
      await WesiHaptics.warmUp();

      expect(WesiHaptics.precise, isFalse);
      expect(WesiHaptics.hasVibrator, isTrue);
    });

    test('спрашиваем один раз, а не на каждое нажатие', () async {
      answer((_) async => {'precise': true, 'hasVibrator': true});
      await WesiHaptics.warmUp();
      await WesiHaptics.warmUp();
      await WesiHaptics.warmUp();

      expect(calls.where((c) => c.method == 'capabilities').length, 1);
    });

    test('нет канала — значит нет точного отклика', () async {
      // Так выглядит компьютер и любая платформа без нативной части.
      answer((_) async => throw MissingPluginException());
      await WesiHaptics.warmUp();

      expect(WesiHaptics.precise, isFalse);
    });
  });

  group('проигрывание', () {
    test('событие уходит своим именем', () async {
      answer((_) async => true);

      for (final kind in FeedbackKind.values) {
        await WesiHaptics.play(kind.name);
      }

      expect(
        [for (final c in calls) c.arguments['effect']],
        [for (final k in FeedbackKind.values) k.name],
        reason: 'нативная сторона различает события по имени, и подмена '
            'здесь означала бы ошибку вместо успеха',
      );
    });

    test('отказ платформы — это false, а не исключение', () async {
      // Отклик не то, ради чего стоит ронять действие человека.
      answer((_) async => throw PlatformException(code: 'no_vibrator'));

      expect(await WesiHaptics.play('tap'), isFalse);
    });

    test('нативная сторона не взялась — тоже false', () async {
      // Так она сообщает «сделай сам»: дальше идёт штатный HapticFeedback.
      answer((_) async => false);

      expect(await WesiHaptics.play('tap'), isFalse);
    });
  });
}
