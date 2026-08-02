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
  });

  ArticleModel copyWith({
    String? title,
    String? body,
    ArticleSection? section,
    List<String>? tags,
    DateTime? updatedAt,
    bool? pinned,
    String? parentId,
    bool? isFolder,
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
        parentId: parentId ?? this.parentId,
        isFolder: isFolder ?? this.isFolder,
      );

  /// Первые строки для превью в списке.
  String get excerpt {
    var plain = body;
    if (plain.trimLeft().startsWith('[')) {
      try {
        final buf = StringBuffer();
        final re = RegExp(r'"insert"\s*:\s*"((?:\.|[^"\])*)"');
        for (final m in re.allMatches(plain)) {
          final chunk = m.group(1)!;
          buf.write(chunk
              .replaceAll('
', ' ')
              .replaceAll(r'"', '"'));
        }
        plain = buf.toString();
      } catch (_) {}
    }
    plain = plain
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
    return title.toLowerCase().contains(q) ||
        body.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  bool get isRichBody {
    final t = body.trimLeft();
    return t.startsWith('[') || t.startsWith('{');
  }
}
