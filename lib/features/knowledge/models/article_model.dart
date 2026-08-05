import 'dart:convert';

import 'package:hive/hive.dart';

part 'article_model.g.dart';

/// Раздел базы знаний.
@HiveType(typeId: 16)
enum ArticleSection {
  @HiveField(0)
  about,
  @HiveField(1)
  playbook,
  @HiveField(2)
  guide,
  @HiveField(3)
  finance,
  @HiveField(4)
  personal,
}

/// Название раздела для человека.
///
/// Живёт рядом с самим перечислением, потому что раздел показывается в двух
/// местах — чипами на экране базы и переключателем в редакторе. Названия
/// стояли там по отдельности и разошлись: один и тот же раздел назывался
/// «Регламенты» в одном месте и «Работа» в другом.
extension ArticleSectionLabel on ArticleSection {
  String label(bool russian) => switch (this) {
        ArticleSection.about => russian ? 'О системе' : 'About',
        ArticleSection.guide => russian ? 'Инструкции' : 'How-to',
        ArticleSection.playbook => russian ? 'Работа' : 'Work',
        ArticleSection.finance => russian ? 'Деньги' : 'Money',
        ArticleSection.personal => russian ? 'Жизнь' : 'Life',
      };
}

/// Статья базы знаний.
///
/// [body] — либо Quill Delta JSON (после rich-редактора), либо старый
/// plain/Markdown текст. Рендерер сам определяет формат.
///
/// [parentId] — ID родительской статьи. Если null — корневая.
/// [isFolder] — true = папка (может содержать дочерние статьи).
@HiveType(typeId: 17)
class ArticleModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String body;

  @HiveField(3)
  final ArticleSection section;

  @HiveField(4)
  final List<String> tags;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  final DateTime updatedAt;

  /// Встроенная статья — та, что поставляется с приложением («О программе»).
  /// Её нельзя удалить: иначе справка исчезала бы навсегда после случайного
  /// свайпа, и восстановить её было бы нечем.
  @HiveField(7)
  final bool builtIn;

  @HiveField(8)
  final bool pinned;

  /// ID родительской статьи. null = корневая (верхний уровень).
  @HiveField(9)
  final String? parentId;

  /// true = папка (контейнер для дочерних статей).
  /// Папки имеют body, но основное назначение — группировка.
  @HiveField(10)
  final bool isFolder;

  /// Место в папке. null — «куда попадёт».
  ///
  /// Нужно потому, что путеводитель — это последовательность: «первый день»
  /// обязан стоять раньше «если что-то пошло не так». Сортировка по
  /// алфавиту или по дате правки ставила бы их как придётся, и человек
  /// читал бы главы вразнобой, не понимая, что их вообще читают подряд.
  ///
  /// Поле nullable намеренно: на устройствах уже лежат записи без него, и
  /// non-nullable `int` сломал бы им чтение (Hive пишет `fields[11] as int`).
  @HiveField(11)
  final int? orderRaw;

  /// Место в папке; у чужих записей — в конец.
  int get order => orderRaw ?? 10000;

  const ArticleModel({
    required this.id,
    required this.title,
    required this.body,
    this.section = ArticleSection.playbook,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.builtIn = false,
    this.pinned = false,
    this.parentId,
    this.isFolder = false,
    this.orderRaw,
  });

  /// Отличает «параметр не передали» от «передали null».
  ///
  /// Для parentId это принципиально: null — осмысленное значение, «лежит в
  /// корне». С обычным `parentId ?? this.parentId` статью можно было
  /// положить в папку, но нельзя вынуть обратно: выбор «в корень» давал
  /// null, а copyWith молча возвращал прежнего родителя. Со стороны это и
  /// выглядело как «дерево не работает».
  static const Object _unset = Object();

  ArticleModel copyWith({
    String? title,
    String? body,
    ArticleSection? section,
    List<String>? tags,
    DateTime? updatedAt,
    bool? pinned,
    Object? parentId = _unset,
    bool? isFolder,
    int? orderRaw,
  }) =>
      ArticleModel(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        section: section ?? this.section,
        tags: tags ?? this.tags,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        builtIn: builtIn,
        pinned: pinned ?? this.pinned,
        parentId: identical(parentId, _unset)
            ? this.parentId
            : parentId as String?,
        isFolder: isFolder ?? this.isFolder,
        orderRaw: orderRaw ?? this.orderRaw,
      );

  /// Текст статьи без разметки — для превью и для поиска.
  ///
  /// Тело редактора хранится как Delta-документ Quill (JSON), и раньше его
  /// разбирали регулярным выражением. Выражение было написано с ошибкой в
  /// экранировании (`[^"\]` вместо `[^"\\]`), `RegExp` падал прямо на
  /// создании, исключение глотал `catch`, и в списке вместо текста статьи
  /// показывался сырой JSON.
  ///
  /// Разбирать JSON регулярным выражением не нужно и не следует: любое
  /// экранирование внутри строки ломает разбор заново. Здесь настоящий
  /// `jsonDecode` — он же сам снимает `\n` и `\"`.
  String get plainText {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('[')) return body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return body;
      final buf = StringBuffer();
      for (final op in decoded) {
        if (op is! Map) continue;
        final insert = op['insert'];
        // Картинки и прочие вставки приходят объектом — в текст не идут.
        if (insert is String) buf.write(insert);
      }
      final text = buf.toString().trim();
      return text.isEmpty ? body : text;
    } catch (_) {
      // Тело не Delta, а просто текст, начинающийся со скобки.
      return body;
    }
  }

  /// Первые строки для превью в списке.
  String get excerpt {
    final plain = plainText
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[*_`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length <= 140) return plain;
    return '${plain.substring(0, 140)}…';
  }

  bool matches(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    // По plainText, а не по body: в body лежит JSON, и поиск по нему и
    // находил служебные слова вроде «insert», и не находил текст, если тот
    // разбит на несколько фрагментов разметкой.
    return title.toLowerCase().contains(q) ||
        plainText.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  bool get isRichBody {
    final t = body.trimLeft();
    return t.startsWith('[') || t.startsWith('{');
  }
}
