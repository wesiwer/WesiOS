import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/chat_policy.dart';

/// Куда разрешено отправлять переписку ради разметки тем.
///
/// **Почему это выбор, а не константа.** Разбиение на темы — ключевая часть
/// чатов, и делать его хорошо без модели нельзя. Но «включить модель» — это
/// не одно решение, а три разных, с очень разной ценой.
enum TopicPrivacyMode {
  /// Ничего не уходит с устройства. Темы размечаются словами-ключами:
  /// границы находятся, названия — перечень характерных слов.
  device,

  /// Уходит на **свой** сервер — туда же, где уже лежат данные.
  ///
  /// Середина, которой я сначала не назвал, а зря: переписка покидает
  /// телефон, но не покидает вашу инфраструктуру. Для рабочего мессенджера
  /// это совсем не то же самое, что отдать её чужой компании.
  ownServer,

  /// Уходит любому настроенному поставщику, включая внешнего.
  ///
  /// Лучшее качество разметки и худшая приватность: фрагменты переписки
  /// оказываются у третьей стороны.
  anyModel,
}

/// Кому и что можно показывать ради разметки тем.
///
/// **Главное правило этого файла: интерфейс обязан говорить правду.** Что бы
/// здесь ни было выбрано, подпись под чатом должна соответствовать
/// действительности. Обещание «переписку видят только собеседники»,
/// оставленное при включённой внешней модели, — это не приватность, а ложь о
/// ней, и она хуже честного «читает модель».
class TopicPrivacy {
  static const String _box = 'wesios_settings';
  static const String _modeKey = 'topic_privacy_mode';

  /// Меняется при смене режима — подписи в чатах перечитываются.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// По умолчанию — свой сервер.
  ///
  /// Не «на устройстве»: владелец прямо сказал, что работа с блоками важнее
  /// полной закрытости. И не «любая модель»: включать отправку переписки
  /// третьей стороне молча, по умолчанию, нельзя — такое решение человек
  /// должен принять сам и осознанно.
  static const TopicPrivacyMode defaultMode = TopicPrivacyMode.ownServer;

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  static TopicPrivacyMode get mode {
    final raw = _open()?.get(_modeKey);
    if (raw is! String) return defaultMode;
    for (final m in TopicPrivacyMode.values) {
      if (m.name == raw) return m;
    }
    return defaultMode;
  }

  static Future<void> setMode(TopicPrivacyMode value) async {
    await _open()?.put(_modeKey, value.name);
    revision.value++;
  }

  /// Считается ли настроенная модель своей.
  ///
  /// Определяется по адресу: свой сервер — это не api.openai.com и не другой
  /// известный поставщик. Проверка грубая, поэтому она работает только в
  /// сторону запрета: незнакомый адрес считается своим лишь тогда, когда
  /// владелец сам выбрал режим «свой сервер».
  static bool looksExternal(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    const known = [
      'openai.com', 'anthropic.com', 'googleapis.com', 'mistral.ai',
      'groq.com', 'together.ai', 'deepseek.com', 'openrouter.ai',
    ];
    return known.any((k) => host == k || host.endsWith('.$k'));
  }

  /// Можно ли отдать этот чат внешнему судье при текущих настройках.
  static bool mayLeaveDevice(ChatKind kind, {String? baseUrl}) {
    switch (mode) {
      case TopicPrivacyMode.device:
        return false;
      case TopicPrivacyMode.ownServer:
        // Рабочий чат владелец и так читает — сюда он уйдёт при любом
        // адресе. Личный — только если модель действительно своя.
        if (kind == ChatKind.work) return true;
        return baseUrl == null || !looksExternal(baseUrl);
      case TopicPrivacyMode.anyModel:
        return true;
    }
  }

  /// Кто фактически может прочитать переписку этого типа — одной строкой.
  ///
  /// Именно это показывается человеку под чатом. Строка собирается из
  /// настроек, а не пишется вручную: подпись, которую надо не забыть
  /// поправить вслед за настройкой, рано или поздно начнёт врать.
  static String describe(ChatKind kind, {bool russian = true}) {
    final owner = ChatEnvelopePolicy.ownerCanRead(kind);
    final ai = mayLeaveDevice(kind);

    if (!russian) {
      final who = <String>[
        'participants',
        if (owner) 'the owner',
        if (ai) 'the topic model',
      ];
      return 'Readable by: ${who.join(', ')}.';
    }

    final who = <String>[
      'собеседники',
      if (owner) 'владелец',
      if (ai) _modelWord(),
    ];
    return 'Читают: ${who.join(', ')}.';
  }

  static String _modelWord() => switch (mode) {
        TopicPrivacyMode.anyModel => 'внешняя модель разметки',
        _ => 'модель разметки на вашем сервере',
      };

  static String labelRu(TopicPrivacyMode m) => switch (m) {
        TopicPrivacyMode.device => 'Только на устройстве',
        TopicPrivacyMode.ownServer => 'Через мою модель',
        TopicPrivacyMode.anyModel => 'Через любую модель',
      };

  static String hintRu(TopicPrivacyMode m) => switch (m) {
        TopicPrivacyMode.device =>
          'Ничего не уходит наружу. Границы тем находятся, но называются '
              'перечнем слов, а не по смыслу.',
        TopicPrivacyMode.ownServer =>
          'Фрагменты уходят на ваш сервер — туда же, где уже лежат данные. '
              'Телефон переписка покидает, вашу инфраструктуру — нет.',
        TopicPrivacyMode.anyModel =>
          'Лучшая разметка. Фрагменты переписки оказываются у стороннего '
              'поставщика — включая личные чаты.',
      };
}
