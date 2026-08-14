import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_voice_session.dart';

/// Голосовой разговор: слушает, отправляет, озвучивает, снова слушает.
///
/// До этого голос был диктовкой: микрофон наполнял поле ввода, а решение
/// «фраза закончилась» принимал человек нажатием. Разговором это не
/// становится — набор текста голосом им не является.
///
/// Ошибки здесь дорогие и почти все невидимые в коде: микрофон, услышавший
/// собственную озвучку, уводит разговор в бесконечную петлю без единого
/// слова снаружи; уточнение распознавания, пришедшее на миллисекунду позже
/// решения об отправке, отправляет ту же фразу дважды; ответ на отменённую
/// фразу договаривается в уже выключенном разговоре. Поэтому проверяется
/// именно порядок событий, а не только конечное состояние.
void main() {
  _Ear ear() => _Ear();

  test('полный круг: услышал, отправил, озвучил, снова слушает', () async {
    final e = ear();
    final m = _Mouth();
    final sent = <String>[];
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: m,
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (text) async {
        sent.add(text);
        return [const WesiAiSpokenReply('Готово', author: WesiAiMessageAuthor.zane)];
      },
    );

    await session.start();
    expect(session.phase, WesiAiVoicePhase.listening);

    e.say('сделай бит');
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(sent, ['сделай бит']);
    expect(m.spoken, ['Готово']);
    expect(session.phase, WesiAiVoicePhase.listening,
        reason: 'после ответа микрофон обязан открыться снова');
    session.dispose();
  });

  test('пауза внутри фразы её не обрывает', () async {
    // Человек делает вдох посреди предложения. Если считать это концом
    // фразы, система перебьёт его на первой же паузе.
    final e = ear();
    final sent = <String>[];
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: _Mouth(),
      silence: const Duration(milliseconds: 60),
      echoGuard: Duration.zero,
      onTurn: (text) async {
        sent.add(text);
        return const [];
      },
    );

    await session.start();
    e.say('сделай');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    e.say('сделай бит');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(sent, isEmpty, reason: 'фраза ещё продолжалась');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sent, ['сделай бит']);
    session.dispose();
  });

  test('микрофон закрыт, пока идёт озвучка', () async {
    // Иначе распознавание услышит собственный голос из динамика, примет
    // его за речь человека и ответит само себе.
    final e = ear();
    final m = _Mouth();
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: m,
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (_) async =>
          [const WesiAiSpokenReply('Отвечаю', author: WesiAiMessageAuthor.zane)],
    );
    m.onSpeak = () {
      expect(e.listening, isFalse,
          reason: 'микрофон открыт во время озвучки — это петля');
    };

    await session.start();
    e.say('привет');
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(m.spoken, ['Отвечаю']);
    session.dispose();
  });

  test('фраза не уходит дважды', () async {
    // Распознавание любит прислать уточнение сразу после того, как решение
    // об отправке уже принято. Без защиты в чат уходят два одинаковых
    // сообщения и приходят два ответа подряд.
    final e = ear();
    final sent = <String>[];
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: _Mouth(),
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (text) async {
        sent.add(text);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const [];
      },
    );

    await session.start();
    e.say('одна фраза');
    await Future<void>.delayed(const Duration(milliseconds: 35));
    // Уточнение приходит уже после решения отправить.
    e.say('одна фраза.');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(sent, hasLength(1));
    session.dispose();
  });

  test('пустая тишина ничего не отправляет', () async {
    final e = ear();
    final sent = <String>[];
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: _Mouth(),
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (text) async {
        sent.add(text);
        return const [];
      },
    );

    await session.start();
    e.say('   ');
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(sent, isEmpty);
    expect(session.phase, WesiAiVoicePhase.listening);
    session.dispose();
  });

  group('лобби', () {
    test('каждый отвечает своим голосом', () async {
      // Склеить две реплики в одну строку значило бы озвучить диалог двух
      // людей одним голосом.
      final e = ear();
      final m = _Mouth();
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [
          WesiAiSpokenReply('Зейн говорит', author: WesiAiMessageAuthor.zane),
          WesiAiSpokenReply('Нирвана говорит',
              author: WesiAiMessageAuthor.nirvana),
        ],
      );

      await session.start();
      e.say('что думаете');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(m.spoken, ['Зейн говорит', 'Нирвана говорит']);
      expect(m.authors,
          [WesiAiMessageAuthor.zane, WesiAiMessageAuthor.nirvana]);
      session.dispose();
    });
  });

  group('состояния видны снаружи', () {
    test('слушаю → думаю → говорит Зейн → слушаю', () async {
      final e = ear();
      final m = _Mouth();
      final phases = <WesiAiVoicePhase>[];
      late WesiAiVoiceSession session;
      session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const [
            WesiAiSpokenReply('Отвечаю', author: WesiAiMessageAuthor.zane)
          ];
        },
      );
      session.addListener(() {
        if (phases.isEmpty || phases.last != session.phase) {
          phases.add(session.phase);
        }
      });

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        phases,
        containsAllInOrder([
          WesiAiVoicePhase.listening,
          WesiAiVoicePhase.thinking,
          WesiAiVoicePhase.speaking,
          WesiAiVoicePhase.listening,
        ]),
      );
      session.dispose();
    });

    test('во время озвучки видно, кто именно говорит', () async {
      final e = ear();
      final m = _Mouth();
      WesiAiMessageAuthor? seen;
      late WesiAiVoiceSession session;
      session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [
          WesiAiSpokenReply('Отвечаю', author: WesiAiMessageAuthor.nirvana)
        ],
      );
      m.onSpeak = () => seen = session.speaker;

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(seen, WesiAiMessageAuthor.nirvana);
      expect(session.speaker, isNull, reason: 'озвучка кончилась');
      session.dispose();
    });
  });

  group('перебивание', () {
    test('нажатие обрывает озвучку и возвращает микрофон', () async {
      final e = ear();
      final m = _Mouth(speakFor: const Duration(milliseconds: 200));
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [
          WesiAiSpokenReply('Очень длинный ответ',
              author: WesiAiMessageAuthor.zane)
        ],
      );

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(session.phase, WesiAiVoicePhase.speaking);

      await session.bargeIn();

      expect(m.stopped, greaterThan(0), reason: 'озвучка обязана замолчать');
      expect(session.phase, WesiAiVoicePhase.listening);
      session.dispose();
    });

    test('перебитый ответ не договаривает вторую реплику', () async {
      // В лобби ответов несколько. Перебивание на первом не должно
      // приводить к тому, что вторая реплика всё равно прозвучит.
      final e = ear();
      final m = _Mouth(speakFor: const Duration(milliseconds: 120));
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [
          WesiAiSpokenReply('Первый', author: WesiAiMessageAuthor.zane),
          WesiAiSpokenReply('Второй', author: WesiAiMessageAuthor.nirvana),
        ],
      );

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await session.bargeIn();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(m.spoken, ['Первый']);
      session.dispose();
    });
  });

  group('выключение', () {
    test('останавливает и микрофон, и голос', () async {
      final e = ear();
      final m = _Mouth(speakFor: const Duration(milliseconds: 200));
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [
          WesiAiSpokenReply('Ответ', author: WesiAiMessageAuthor.zane)
        ],
      );

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await session.stop();

      expect(session.phase, WesiAiVoicePhase.off);
      expect(session.active, isFalse);
      expect(m.stopped, greaterThan(0));
      expect(e.cancelled, greaterThan(0));
      session.dispose();
    });

    test('ответ на выключенный разговор не звучит', () async {
      // Сеть медленная, человек успел выйти. Договаривать ответ в
      // выключенном разговоре нельзя.
      final e = ear();
      final m = _Mouth();
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: m,
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return const [
            WesiAiSpokenReply('Поздний ответ', author: WesiAiMessageAuthor.zane)
          ];
        },
      );

      await session.start();
      e.say('вопрос');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.phase, WesiAiVoicePhase.thinking);
      await session.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(m.spoken, isEmpty);
      expect(session.phase, WesiAiVoicePhase.off);
      session.dispose();
    });

    test('повторный запуск не удваивает разговор', () async {
      final e = ear();
      final session = WesiAiVoiceSession(
        ear: e,
        mouth: _Mouth(),
        silence: const Duration(milliseconds: 30),
        echoGuard: Duration.zero,
        onTurn: (_) async => const [],
      );

      await session.start();
      await session.start();

      expect(e.starts, 1);
      session.dispose();
    });
  });

  test('недоступный микрофон гасит разговор с причиной', () async {
    final e = ear()..canStart = false;
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: _Mouth(),
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (_) async => const [],
    );

    await session.start();

    expect(session.phase, WesiAiVoicePhase.off);
    expect(session.error, isNotNull);
    session.dispose();
  });

  test('сбой отправки возвращает разговор к слушанию', () async {
    // Разговор не должен молча умирать от одной неудачной отправки.
    final e = ear();
    final session = WesiAiVoiceSession(
      ear: e,
      mouth: _Mouth(),
      silence: const Duration(milliseconds: 30),
      echoGuard: Duration.zero,
      onTurn: (_) async => throw StateError('сеть недоступна'),
    );

    await session.start();
    e.say('вопрос');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(session.phase, WesiAiVoicePhase.listening);
    expect(session.error, contains('сеть недоступна'));
    session.dispose();
  });
}

/// Микрофон под управлением теста.
class _Ear extends ChangeNotifier implements WesiAiVoiceEar {
  bool canStart = true;
  bool listening = false;
  int starts = 0;
  int cancelled = 0;
  String _transcript = '';

  /// Человек произнёс очередной кусок.
  void say(String text) {
    _transcript = text;
    notifyListeners();
  }

  @override
  Future<bool> start() async {
    if (!canStart) return false;
    starts++;
    listening = true;
    return true;
  }

  @override
  Future<void> stop() async => listening = false;

  @override
  Future<void> cancel() async {
    cancelled++;
    listening = false;
    _transcript = '';
  }

  @override
  String get transcript => _transcript;

  @override
  void clearTranscript() => _transcript = '';
}

/// Голос под управлением теста.
class _Mouth implements WesiAiVoiceMouth {
  final Duration speakFor;
  final List<String> spoken = [];
  final List<WesiAiMessageAuthor?> authors = [];
  int stopped = 0;
  VoidCallback? onSpeak;
  bool _interrupted = false;

  _Mouth({this.speakFor = Duration.zero});

  @override
  Future<void> speak(String text, {WesiAiMessageAuthor? author}) async {
    spoken.add(text);
    authors.add(author);
    onSpeak?.call();
    _interrupted = false;
    if (speakFor > Duration.zero) {
      final deadline = DateTime.now().add(speakFor);
      while (DateTime.now().isBefore(deadline) && !_interrupted) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  @override
  Future<void> stop() async {
    stopped++;
    _interrupted = true;
  }
}
