import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import 'topic_chunker.dart';
import 'topic_judge.dart';

/// Настройки доступа к модели.
///
/// Адрес намеренно настраиваемый: одна и та же схема подходит и к OpenAI, и
/// к своему прокси на сервере в Нидерландах, и к модели, поднятой локально
/// (llama.cpp и подобные отвечают тем же протоколом). Привязываться к одному
/// поставщику в приложении, которое должно работать из России, — плохая идея.
class AiEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'ai_base_url';
  static const String _modelKey = 'ai_model';
  static const String _keyName = 'ai_api_key';

  static const String defaultUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  static String get baseUrl {
    final v = _open()?.get(_urlKey);
    return (v is String && v.trim().isNotEmpty) ? v.trim() : defaultUrl;
  }

  static String get model {
    final v = _open()?.get(_modelKey);
    return (v is String && v.trim().isNotEmpty) ? v.trim() : defaultModel;
  }

  /// Ключ лежит там же, где остальные ключи сервисов, и приезжает вместе с
  /// ними — человеку не надо вводить его руками.
  static String? get apiKey {
    final v = _open()?.get(_keyName);
    return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
  }

  static bool get configured => apiKey != null;

  static Future<void> configure({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) async {
    final box = _open();
    if (box == null) return;
    if (baseUrl != null) await box.put(_urlKey, baseUrl.trim());
    if (model != null) await box.put(_modelKey, model.trim());
    if (apiKey != null) await box.put(_keyName, apiKey.trim());
  }
}

/// Как сходить к модели. Отдельно, чтобы разбор ответа проверялся тестами
/// без сети.
typedef ChatCompletion = Future<String?> Function(String systemPrompt,
    String userPrompt);

/// Разметка тем моделью.
///
/// Модель получает **только спорный кусок** — несколько сообщений вокруг
/// предполагаемой границы, которые нашла местная разметка. Не весь чат: это
/// были бы деньги, задержка на каждое сообщение и отправка наружу гораздо
/// большего, чем нужно.
///
/// Ответ просим строго в JSON и разбираем строго. Модель, ответившая
/// рассуждением вместо ответа, для нас всё равно что не ответила: подставлять
/// в интерфейс «Конечно! Вот моё мнение:» нельзя.
class AiTopicJudge implements TopicJudge {
  final ChatCompletion _complete;

  AiTopicJudge({ChatCompletion? complete})
      : _complete = complete ?? _httpCompletion;

  @override
  bool get available => AiEndpoint.configured;

  @override
  String get name => 'Wesi AI';

  static const String _systemBoundary =
      'Ты помогаешь разбивать деловую переписку на осознанные темы. '
      'Отвечай ТОЛЬКО объектом JSON без пояснений и без markdown. '
      'Поля: split (true/false) — начинается ли после разрыва новая тема; '
      'title (строка, 2-4 слова на русском) — название новой темы; '
      'confidence (число 0..1); reason (строка, одно короткое предложение '
      'по-русски, объясняющее решение человеку).';

  static const String _systemTitle =
      'Назови тему делового разговора. Отвечай ТОЛЬКО объектом JSON без '
      'пояснений: {"title": "2-4 слова на русском"}. '
      'Название должно говорить о сути, а не пересказывать реплики.';

  @override
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  }) async {
    if (!available) return null;
    final prompt = StringBuffer()
      ..writeln('Сообщения ДО предполагаемой границы:')
      ..writeln(_render(before))
      ..writeln()
      ..writeln('Сообщения ПОСЛЕ:')
      ..writeln(_render(after));

    final raw = await _complete(_systemBoundary, prompt.toString());
    return parseVerdict(raw);
  }

  @override
  Future<String?> nameTopic(List<ChunkInput> messages) async {
    if (!available) return null;
    final raw = await _complete(_systemTitle, _render(messages));
    final json = _json(raw);
    final title = json?['title'];
    return title is String && title.trim().isNotEmpty ? title.trim() : null;
  }

  /// Разбор ответа. Открыт для тестов: именно здесь ломается всё, что
  /// связано с моделями, и проверять это надо без сети.
  static TopicVerdict? parseVerdict(String? raw) {
    final json = _json(raw);
    if (json == null) return null;
    final split = json['split'];
    if (split is! bool) return null;

    final conf = json['confidence'];
    return TopicVerdict(
      split: split,
      title: json['title'] is String ? (json['title'] as String).trim() : '',
      confidence: conf is num ? conf.toDouble().clamp(0.0, 1.0) : 0.5,
      reason: json['reason'] is String ? (json['reason'] as String).trim() : '',
    );
  }

  /// Достаёт объект JSON из ответа.
  ///
  /// Модели любят обернуть ответ в ```json … ``` или добавить фразу перед
  /// ним, даже когда просили не делать этого. Требовать идеального
  /// послушания бессмысленно — дешевле вырезать объект по фигурным скобкам.
  static Map<String, dynamic>? _json(String? raw) {
    if (raw == null) return null;
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Переписка для модели — без идентификаторов и без времени с точностью до
  /// секунды: лишние подробности не помогают понять тему, а утекают вместе
  /// со всем остальным.
  static String _render(List<ChunkInput> messages) {
    final names = <String, String>{};
    final buf = StringBuffer();
    for (final m in messages) {
      final who = names.putIfAbsent(
          m.authorId, () => 'Собеседник ${names.length + 1}');
      buf.writeln('$who: ${m.text}');
    }
    return buf.toString().trim();
  }

  // -------------------------------------------------------------- сеть

  static Future<String?> _httpCompletion(String system, String user) async {
    final key = AiEndpoint.apiKey;
    if (key == null) return null;
    final uri = Uri.tryParse('${AiEndpoint.baseUrl}/chat/completions');
    if (uri == null) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      req.write(jsonEncode({
        'model': AiEndpoint.model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      }));
      final res = await req.close().timeout(const Duration(seconds: 40));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices.first as Map)['message'];
      final content = message is Map ? message['content'] : null;
      return content is String ? content : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
