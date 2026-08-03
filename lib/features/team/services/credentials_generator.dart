import 'dart:math';

/// Подбор логина и генерация пароля для новой учётной записи.
///
/// Логин человек получает от владельца и потом набирает руками, иногда
/// диктует по телефону. Поэтому он собирается из **нейтральных слов**, а не
/// из имени и фамилии: имя в логине сообщает лишнее любому, кто увидит экран
/// входа, а транслитерация фамилий вдобавок вечно спорная — «Щербаков» можно
/// написать четырьмя способами, и человек будет ошибаться при каждом входе.
class CredentialsGenerator {
  /// Слова для логинов: короткие, нейтральные, однозначные на слух.
  ///
  /// Ни имён, ни слов с двойными буквами и спорной транслитерацией —
  /// логин часто диктуют голосом, и «аллея» превратится в «алея».
  static const List<String> words = [
    'amber', 'anchor', 'arbor', 'atlas', 'aurora', 'basalt', 'beacon',
    'birch', 'bridge', 'cedar', 'cobalt', 'comet', 'copper', 'coral',
    'crystal', 'delta', 'dune', 'ember', 'falcon', 'fjord', 'flint',
    'forest', 'garnet', 'glacier', 'granite', 'harbor', 'haven', 'horizon',
    'indigo', 'ivory', 'jasper', 'juniper', 'kernel', 'lagoon', 'lantern',
    'lattice', 'lunar', 'magnet', 'maple', 'marble', 'meadow', 'meridian',
    'mesa', 'meteor', 'nebula', 'nickel', 'north', 'oasis', 'obsidian',
    'onyx', 'opal', 'orbit', 'pebble', 'pillar', 'pine', 'plateau',
    'polar', 'prism', 'quartz', 'quill', 'rapid', 'reef', 'ridge',
    'river', 'sable', 'sage', 'sandbar', 'sapphire', 'shale', 'silver',
    'slate', 'solar', 'spruce', 'stellar', 'stone', 'summit', 'sunset',
    'tempo', 'terra', 'thistle', 'tidal', 'timber', 'topaz', 'tundra',
    'valley', 'vector', 'verdant', 'vertex', 'vista', 'walnut', 'willow',
    'zenith', 'zephyr',
  ];

  /// Знаки для пароля.
  ///
  /// Убраны те, что путаются при чтении и надиктовке: `0` и `O`, `1`, `l` и
  /// `I`, `5` и `S`. Пароль всё равно временный — человек сменит его на свой,
  /// — и главное здесь, чтобы он ввёлся с первого раза, а не был максимально
  /// стойким. Длина компенсирует урезанный алфавит.
  static const String _passwordAlphabet =
      'abcdefghijkmnpqrtuvwxyzABCDEFGHJKLMNPQRTUVWXYZ2346789';

  /// Длина пароля по умолчанию.
  ///
  /// 14 знаков из 53-символьного алфавита — это около 80 бит. Перебор
  /// бессмыслен, при этом строка ещё диктуется голосом без мучений.
  static const int defaultPasswordLength = 14;

  static final Random _rng = Random.secure();

  /// Свободный логин, которого нет среди [taken].
  ///
  /// Сначала пробует чистое слово, потом слово с числом. Возвращает null,
  /// только если исчерпаны все варианты, — но при 93 словах и четырёхзначных
  /// числах этого не случится раньше, чем кончатся сотрудники на планете.
  static String? pick(Set<String> taken, {Random? random}) {
    final rng = random ?? _rng;
    final free = words.where((w) => !taken.contains(w)).toList();
    if (free.isNotEmpty) return free[rng.nextInt(free.length)];

    // Слова кончились — добавляем число. Пробуем ограниченное число раз,
    // чтобы не зациклиться: бесконечный цикл в подборе логина повесил бы
    // интерфейс намертво.
    for (var attempt = 0; attempt < 200; attempt++) {
      final candidate =
          '${words[rng.nextInt(words.length)]}${rng.nextInt(9000) + 1000}';
      if (!taken.contains(candidate)) return candidate;
    }
    return null;
  }

  /// Случайный пароль.
  ///
  /// Random.secure() — криптографический источник. Обычный Random предсказуем
  /// по времени запуска, и пароли, выданные подряд нескольким сотрудникам,
  /// оказались бы связаны между собой.
  static String password({int length = defaultPasswordLength}) {
    if (length < 8) length = 8;
    return List.generate(
      length,
      (_) => _passwordAlphabet[_rng.nextInt(_passwordAlphabet.length)],
    ).join();
  }

  /// Приводит логин к тому виду, в котором он хранится и сравнивается.
  ///
  /// Регистр не учитывается намеренно: человек, которому продиктовали
  /// «Amber», наберёт «amber» и не поймёт, почему не пускает.
  static String normalize(String login) =>
      login.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// Годится ли строка как логин.
  ///
  /// Только латиница, цифры, точка, дефис и подчёркивание: логин становится
  /// частью адреса `<логин>@…`, а там остальное недопустимо.
  static bool isValid(String login) {
    final normalized = normalize(login);
    if (normalized.length < 3 || normalized.length > 32) return false;
    return RegExp(r'^[a-z0-9][a-z0-9._-]*[a-z0-9]$').hasMatch(normalized);
  }

  /// Адрес для Firebase Auth.
  ///
  /// Firebase требует именно почту, а владелец хочет выдавать короткие
  /// логины. Служебный домен решает оба требования: адрес формально
  /// правильный, писем туда никто не шлёт.
  ///
  /// Плата за это названа честно: восстановление пароля письмом на такой
  /// адрес не работает — сбрасывать будет владелец или бот.
  static String toEmail(String login, {String domain = 'wesi.local'}) =>
      '${normalize(login)}@$domain';

  /// Обратное преобразование — для показа человеку.
  static String fromEmail(String email) {
    final at = email.indexOf('@');
    return at <= 0 ? email : email.substring(0, at);
  }
}
