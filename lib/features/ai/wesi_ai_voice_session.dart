import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/wesi_ai_chat_models.dart';

/// Что делает разговор прямо сейчас.
enum WesiAiVoicePhase {
  /// Разговор выключен.
  off,

  /// Микрофон открыт, система ждёт речь.
  listening,

  /// Фраза отправлена, ответ ещё не пришёл.
  thinking,

  /// Ответ озвучивается.
  speaking,
}

/// Реплика, которую нужно произнести, и чьим голосом.
///
/// Список таких реплик, а не одна строка: в лобби на одну фразу человека
/// отвечают оба, и каждый обязан звучать своим голосом. Склеить их в один
/// текст значило бы озвучить диалог двух людей одним голосом.
class WesiAiSpokenReply {
  final String text;
  final WesiAiMessageAuthor? author;

  const WesiAiSpokenReply(this.text, {this.author});
}

/// Что из появившихся сообщений нужно произнести.
///
/// Отбор именно из переписки, а не из отдельного ответа сети: озвучивать
/// нужно ровно то, что человек увидит на экране, и сообщение обязано
/// попасть в чат один раз. В лобби на одну фразу отвечают оба, и каждый
/// ответ сохраняет своего автора — иначе диалог двоих прозвучит одним
/// голосом.
///
/// Ошибку произнести нужно: в разговоре человек не смотрит на экран, и
/// молчание после вопроса неотличимо от поломки. А вот картинку, файл или
/// служебную отметку — нет: осмысленного текста в них нет.
List<WesiAiSpokenReply> spokenRepliesFrom({
  required List<WesiAiMessage> messages,
  required Set<String> alreadySeen,
}) =>
    messages
        .where((m) => !alreadySeen.contains(m.id))
        .where((m) =>
            m.author != WesiAiMessageAuthor.user &&
            m.author != WesiAiMessageAuthor.tool)
        .where((m) =>
            m.kind == WesiAiMessageKind.text ||
            m.kind == WesiAiMessageKind.error)
        .where((m) => m.text.trim().isNotEmpty)
        .map((m) => WesiAiSpokenReply(m.text.trim(), author: m.author))
        .toList(growable: false);

/// Микрофон с точки зрения разговора.
///
/// Интерфейс, а не готовый класс: настоящее распознавание требует
/// разрешений, устройства и живого звука, и проверить на нём логику
/// разговора нельзя. Ошибки же здесь дорогие — застрявший микрофон, немой
/// ответ, отправленная дважды фраза.
abstract class WesiAiVoiceEar implements Listenable {
  Future<bool> start();
  Future<void> stop();
  Future<void> cancel();

  /// Распознанное на текущий момент. Меняется по ходу речи.
  String get transcript;

  /// Слушает ли микрофон прямо сейчас.
  ///
  /// Нужно потому, что распознавание останавливается само: у него свой
  /// предел непрерывного слушания, и по его истечении оно замолкает, никому
  /// об этом не сообщая отдельно. Без этого признака разговор остаётся в
  /// состоянии «слушаю» с мёртвым микрофоном — человек говорит, его никто
  /// не слышит, и на экране всё выглядит исправно.
  bool get listening;

  void clearTranscript();
}

/// Голос с точки зрения разговора.
abstract class WesiAiVoiceMouth {
  /// Возвращает управление, когда произнесено до конца или прервано.
  Future<void> speak(String text, {WesiAiMessageAuthor? author});

  Future<void> stop();
}

/// Отправка фразы и ответ, который нужно произнести.
typedef WesiAiVoiceTurn = Future<List<WesiAiSpokenReply>> Function(String text);

/// Голосовой разговор: слушает, отправляет, озвучивает, снова слушает.
///
/// Это не «микрофон в поле ввода». Разница в том, кто решает, что фраза
/// закончилась. При диктовке решает человек — нажимает «стоп». В разговоре
/// решать должна система, иначе он превращается в набор текста голосом.
///
/// Конец фразы определяется тишиной: пока текст меняется, человек говорит;
/// как только перестал меняться на [silence] — фраза считается законченной
/// и уходит. Порог именно такой длины неслучаен: короче — система перебьёт
/// человека на первой же паузе для вдоха, длиннее — разговор начнёт
/// заметно «висеть» после каждой реплики.
///
/// Микрофон и голос никогда не работают одновременно. Иначе распознавание
/// услышит собственную озвучку из динамика, примет её за речь человека и
/// ответит само себе — разговор уйдёт в петлю без единого слова снаружи.
/// Поэтому порядок строгий: закрыть микрофон, произнести, выждать хвост
/// эха, открыть микрофон.
class WesiAiVoiceSession extends ChangeNotifier {
  final WesiAiVoiceEar ear;
  final WesiAiVoiceMouth mouth;
  final WesiAiVoiceTurn onTurn;

  /// Сколько тишины считать концом фразы.
  final Duration silence;

  /// Пауза между концом озвучки и открытием микрофона.
  ///
  /// Динамик замолкает не мгновенно, и микрофон, открытый в ту же
  /// миллисекунду, ловит хвост собственного голоса.
  final Duration echoGuard;

  WesiAiVoiceSession({
    required this.ear,
    required this.mouth,
    required this.onTurn,
    this.silence = const Duration(milliseconds: 1400),
    this.echoGuard = const Duration(milliseconds: 220),
  }) {
    ear.addListener(_onEar);
  }

  WesiAiVoicePhase _phase = WesiAiVoicePhase.off;
  WesiAiMessageAuthor? _speaker;
  String _heard = '';
  String? _error;
  Timer? _silenceTimer;

  /// Номер круга разговора. Каждый запуск, остановка и перебивание
  /// увеличивают его, и всё, что начиналось на прошлом круге, после этого
  /// само себя отменяет. Без такого счётчика ответ на отменённую фразу
  /// договаривался бы в уже выключенном разговоре.
  int _turnToken = 0;

  /// Идёт ли повторное открытие микрофона. Без флага каждое уведомление
  /// от замолчавшего распознавания запускало бы ещё одну попытку.
  bool _rearming = false;

  WesiAiVoicePhase get phase => _phase;

  /// Кто говорит прямо сейчас. Null — не говорит никто.
  WesiAiMessageAuthor? get speaker =>
      _phase == WesiAiVoicePhase.speaking ? _speaker : null;

  bool get active => _phase != WesiAiVoicePhase.off;

  /// Услышанное на текущий момент — для показа на экране.
  String get heard => _heard;

  String? get error => _error;

  /// Включить разговор.
  Future<void> start() async {
    if (active) return;
    _error = null;
    _turnToken++;
    await _listen(_turnToken);
  }

  /// Выключить разговор целиком.
  Future<void> stop() async {
    _turnToken++;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _phase = WesiAiVoicePhase.off;
    _speaker = null;
    _heard = '';
    notifyListeners();
    await mouth.stop();
    await ear.cancel();
  }

  /// Перебить озвучку и снова слушать.
  ///
  /// Микрофон во время озвучки закрыт намеренно, поэтому услышать начало
  /// речи система не может — перебивание приходит нажатием. Держать
  /// микрофон открытым «на всякий случай» нельзя: без подавления эха он
  /// услышит сам себя, и разговор уйдёт в петлю.
  Future<void> bargeIn() async {
    if (_phase != WesiAiVoicePhase.speaking &&
        _phase != WesiAiVoicePhase.thinking) {
      return;
    }
    final token = ++_turnToken;
    await mouth.stop();
    await _listen(token);
  }

  Future<void> _listen(int token) async {
    if (token != _turnToken) return;
    _rearming = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _heard = '';
    _speaker = null;
    ear.clearTranscript();
    _phase = WesiAiVoicePhase.listening;
    notifyListeners();

    final ok = await ear.start();
    if (token != _turnToken) return;
    if (!ok) {
      _phase = WesiAiVoicePhase.off;
      _error = 'Микрофон недоступен';
      notifyListeners();
    }
  }

  void _onEar() {
    if (_phase != WesiAiVoicePhase.listening) return;

    // Распознавание остановилось само, а сказать ещё ничего не успели.
    // Так бывает после долгой паузы: у плагина есть предел непрерывного
    // слушания, и по его истечении микрофон замолкает. Разговор при этом
    // выглядит живым, но не слышит ничего — молчаливая поломка, самая
    // неприятная из возможных здесь.
    if (!ear.listening && ear.transcript.trim().isEmpty && !_rearming) {
      _rearming = true;
      unawaited(() async {
        final token = _turnToken;
        await ear.start();
        if (token == _turnToken) _rearming = false;
      }());
      return;
    }

    final text = ear.transcript.trim();
    if (text == _heard) return;
    _heard = text;
    notifyListeners();
    _silenceTimer?.cancel();
    if (text.isEmpty) return;
    // Отсчёт начинается заново на каждом изменении текста: пауза внутри
    // фразы не должна её обрывать, а вот пауза после неё — должна.
    _silenceTimer = Timer(silence, _commit);
  }

  Future<void> _commit() async {
    if (_phase != WesiAiVoicePhase.listening) return;
    final text = _heard.trim();
    if (text.isEmpty) return;

    // Фаза переключается до всякого await. Между «решили отправить» и
    // «отправили» микрофон может прислать ещё одно уточнение, и без этой
    // строки та же фраза ушла бы дважды — двумя одинаковыми сообщениями в
    // чате и двумя ответами подряд.
    final token = ++_turnToken;
    _phase = WesiAiVoicePhase.thinking;
    notifyListeners();

    _silenceTimer?.cancel();
    _silenceTimer = null;
    await ear.stop();
    ear.clearTranscript();
    if (token != _turnToken) return;

    List<WesiAiSpokenReply> replies;
    try {
      replies = await onTurn(text);
    } catch (e) {
      if (token != _turnToken) return;
      _error = '$e';
      await _listen(token);
      return;
    }
    if (token != _turnToken) return;

    for (final reply in replies) {
      final clean = reply.text.trim();
      if (clean.isEmpty) continue;
      _phase = WesiAiVoicePhase.speaking;
      _speaker = reply.author;
      notifyListeners();
      await mouth.speak(clean, author: reply.author);
      if (token != _turnToken) return;
    }

    if (echoGuard > Duration.zero) {
      await Future<void>.delayed(echoGuard);
      if (token != _turnToken) return;
    }
    await _listen(token);
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    ear.removeListener(_onEar);
    super.dispose();
  }
}
