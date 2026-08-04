import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/chats/models/chat_policy.dart';
import 'package:wesios/features/chats/services/ai_topic_judge.dart';
import 'package:wesios/features/chats/services/topic_chunker.dart';
import 'package:wesios/features/chats/services/topic_judge.dart';
import 'package:wesios/features/chats/services/topic_refiner.dart';

/// Разметку тем моделью нельзя проверить живой моделью — она отвечает
/// по-разному на один и тот же вход. Поэтому проверяется всё, что вокруг:
/// разбор ответа, поведение при мусоре и молчании, и главное — что личная
/// переписка наружу не уходит ни при каких настройках.
void main() {
  final day = DateTime.utc(2026, 8, 4, 10);

  List<ChunkInput> dialog(List<String> lines) {
    var at = day;
    final out = <ChunkInput>[];
    for (var i = 0; i < lines.length; i++) {
      final p = lines[i].split('|');
      at = at.add(Duration(minutes: int.parse(p[1])));
      out.add(ChunkInput(id: 'm$i', authorId: p[0], at: at, text: p[2]));
    }
    return out;
  }

  final conversation = dialog([
    'a|0|По складу в Химках всё готово, паллеты завезли вчера',
    'b|4|Паллеты принял, разместил в третьем ряду как договаривались',
    'a|50|Про новый прайс для оптовиков подумал, надо пересчитать',
    'b|6|Прайс пересчитаю под новую скидку к пятнице',
    'a|3|Скидку оптовикам оставляем прежнюю, десять процентов',
  ]);

  group('разбор ответа модели', () {
    test('чистый JSON разбирается', () {
      final v = AiTopicJudge.parseVerdict(
          '{"split": true, "title": "Прайс для оптовиков", '
          '"confidence": 0.9, "reason": "речь пошла о ценах"}');
      expect(v, isNotNull);
      expect(v!.split, isTrue);
      expect(v.title, 'Прайс для оптовиков');
      expect(v.confidence, 0.9);
      expect(v.reason, 'речь пошла о ценах');
    });

    test('ответ в ```json … ``` тоже разбирается', () {
      // Модели оборачивают ответ в markdown, даже когда просили не делать
      // этого. Требовать послушания бессмысленно — дешевле вырезать объект.
      final v = AiTopicJudge.parseVerdict('''
Конечно! Вот результат:
```json
{"split": false, "confidence": 0.3}
```
''');
      expect(v, isNotNull);
      expect(v!.split, isFalse);
    });

    test('ответ без поля split — это не ответ', () {
      expect(AiTopicJudge.parseVerdict('{"title": "Что-то"}'), isNull,
          reason: 'подставлять в интерфейс догадку вместо решения нельзя');
    });

    test('рассуждение вместо JSON — не ответ', () {
      expect(
          AiTopicJudge.parseVerdict(
              'Мне кажется, здесь действительно меняется тема, потому что...'),
          isNull);
      expect(AiTopicJudge.parseVerdict(null), isNull);
      expect(AiTopicJudge.parseVerdict(''), isNull);
    });

    test('уверенность вне диапазона подрезается', () {
      expect(
          AiTopicJudge.parseVerdict('{"split": true, "confidence": 7}')!
              .confidence,
          1.0);
      expect(
          AiTopicJudge.parseVerdict('{"split": true, "confidence": -3}')!
              .confidence,
          0.0);
    });

    test('без уверенности берётся середина, а не ноль и не единица', () {
      expect(AiTopicJudge.parseVerdict('{"split": true}')!.confidence, 0.5);
    });
  });

  group('личная переписка', () {
    test('наружу не уходит никогда', () {
      expect(TopicPrivacy.mayLeaveDevice(ChatKind.personal), isFalse);
      expect(TopicPrivacy.mayLeaveDevice(ChatKind.work), isTrue);
    });

    test('судья к личному чату не вызывается вовсе', () async {
      final spy = _SpyJudge();
      final result = await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.personal,
        judge: spy,
      );
      expect(spy.calls, 0,
          reason: 'сквозное шифрование не отменяется ради заголовков');
      expect(result.judgedBy, 'на устройстве');
    });

    test('в рабочем чате судья работает', () async {
      final spy = _SpyJudge();
      await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.work,
        judge: spy,
      );
      expect(spy.calls, greaterThan(0));
    });

    test('отказ объясняется человеку, а не молчит', () {
      final text = TopicPrivacy.explain(ChatKind.personal);
      expect(text, contains('на устройстве'));
      expect(text, isNot(TopicPrivacy.explain(ChatKind.work)));
    });
  });

  group('поведение при отказе модели', () {
    test('молчание модели откатывает к местной разметке', () async {
      final result = await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.work,
        judge: _SilentJudge(),
      );
      expect(result.chunks, isNotEmpty);
      expect(result.questions, isNotEmpty,
          reason: 'тишина хуже, чем разметка попроще');
    });

    test('без ключа судья честно недоступен', () {
      // Бокс настроек в тесте не открыт — ключа нет, значит и модели нет.
      expect(AiTopicJudge().available, isFalse);
    });

    test('«одна тема» от модели убирает вопрос', () async {
      final result = await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.work,
        judge: _FixedJudge(const TopicVerdict(split: false)),
      );
      expect(result.questions, isEmpty);
    });

    test('уверенная модель режет без вопроса', () async {
      final result = await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.work,
        judge: _FixedJudge(const TopicVerdict(
            split: true,
            title: 'Прайс для оптовиков',
            confidence: 0.95,
            reason: 'разговор перешёл к ценам')),
      );
      expect(result.questions, isEmpty);
      expect(result.chunks.length, greaterThan(1));
    });

    test('неуверенная модель даёт вопрос с человеческим названием', () async {
      final result = await TopicRefiner.refine(
        messages: conversation,
        kind: ChatKind.work,
        judge: _FixedJudge(const TopicVerdict(
            split: true,
            title: 'Прайс для оптовиков',
            confidence: 0.6,
            reason: 'дальше речь о ценах')),
      );
      expect(result.questions, isNotEmpty);
      final q = result.questions.first;
      expect(q.suggestedTitle, 'Прайс для оптовиков');
      expect(q.ask(), contains('Прайс для оптовиков'));
      expect(q.ask(), contains('Разделить'));
    });
  });

  group('текст вопроса', () {
    test('без названия спрашивают проще, а не про пустоту', () {
      const q = TopicQuestion(
          index: 2, suggestedTitle: '', reason: 'перерыв', confidence: 0.5);
      expect(q.ask(), isNot(contains('«»')));
      expect(q.ask(), contains('меняет тему'));
    });
  });
}

class _SpyJudge implements TopicJudge {
  int calls = 0;

  @override
  bool get available => true;

  @override
  String get name => 'соглядатай';

  @override
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  }) async {
    calls++;
    return null;
  }

  @override
  Future<String?> nameTopic(List<ChunkInput> messages) async {
    calls++;
    return null;
  }
}

class _SilentJudge implements TopicJudge {
  @override
  bool get available => true;

  @override
  String get name => 'молчун';

  @override
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  }) async =>
      null;

  @override
  Future<String?> nameTopic(List<ChunkInput> messages) async => null;
}

class _FixedJudge implements TopicJudge {
  final TopicVerdict verdict;

  _FixedJudge(this.verdict);

  @override
  bool get available => true;

  @override
  String get name => 'Wesi AI';

  @override
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  }) async =>
      verdict;

  @override
  Future<String?> nameTopic(List<ChunkInput> messages) async =>
      verdict.title.isEmpty ? null : verdict.title;
}
