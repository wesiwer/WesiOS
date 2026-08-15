import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_turn_intent.dart';

void main() {
  group('WesiAiTurnIntentClassifier', () {
    test('explicit stop commands preempt active work', () {
      for (final text in <String>[
        'стой',
        'Стоп',
        'прекрати, это не то',
        'не делай это дальше',
        'дальше не продолжай',
      ]) {
        expect(
          WesiAiTurnIntentClassifier.classify(text, hasActiveWork: true),
          WesiAiTurnIntent.control,
          reason: text,
        );
      }
    });

    test('corrections steer the active task', () {
      for (final text in <String>[
        'Нет, фон должен остаться тёмным',
        'Ты взял не ту версию, нужна 0.23.1+91',
        'Не весь проект, проверяй только Android build',
        'Вместо этого исправь текущий файл',
      ]) {
        expect(
          WesiAiTurnIntentClassifier.classify(text, hasActiveWork: true),
          WesiAiTurnIntent.steer,
          reason: text,
        );
      }
    });

    test('future follow-ups remain deferred', () {
      for (final text in <String>[
        'После этого проверь Windows build',
        'Потом составь отчёт',
        'Когда закончишь, проверь установщик',
        'И отдельно проверь Android icon',
      ]) {
        expect(
          WesiAiTurnIntentClassifier.classify(text, hasActiveWork: true),
          WesiAiTurnIntent.deferred,
          reason: text,
        );
      }
    });

    test('without active work a stop-like text is an ordinary turn', () {
      expect(
        WesiAiTurnIntentClassifier.classify('стой', hasActiveWork: false),
        WesiAiTurnIntent.deferred,
      );
    });

    test('scope-changing corrections invalidate stale deferred work', () {
      expect(
        WesiAiTurnIntentClassifier.invalidatesDeferred(
          'Не весь проект, проверяй только Android',
        ),
        isTrue,
      );
      expect(
        WesiAiTurnIntentClassifier.invalidatesDeferred(
          'Исправь ещё название кнопки',
        ),
        isFalse,
      );
    });
  });
}
