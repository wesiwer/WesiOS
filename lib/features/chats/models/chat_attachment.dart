/// Вложение: файл, приложенный к сообщению.
///
/// **Почему не байтами внутри сообщения.** Договор на три мегабайта,
/// положенный в запись, поедет с ней везде: в память при каждом чтении
/// переписки, в синхронизацию, в резервную копию. Двадцать таких договоров
/// — и открытие чата начинает занимать секунды, а память кончается на
/// телефоне, где её и так мало.
///
/// Поэтому файл лежит на диске, а в сообщении — только описание: как
/// называется, сколько весит, где лежит и какая у него контрольная сумма.
///
/// **Почему хранится картой, а не своим типом Hive.** Новый typeId — это
/// новая запись в списке адаптеров, которую надо не забыть зарегистрировать
/// в четырёх местах, включая тесты. Плоская карта строк читается тем же
/// кодом, что и приезжает с сервера, и не может разойтись с ним по формату.
class ChatAttachment {
  /// Имя, как его видел человек. Показывается в переписке.
  final String name;

  /// Куда положили у себя. Пусто — файла на этом устройстве нет: описание
  /// приехало с сервера, а сам файл ещё не скачан.
  final String path;

  final int sizeBytes;

  /// Тип содержимого — по нему решается, показывать картинку или карточку.
  final String mime;

  /// Контрольная сумма. Нужна, когда файлы начнут ездить между людьми:
  /// иначе подмену или порчу по дороге заметить нечем.
  final String sha256;

  const ChatAttachment({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.mime,
    this.sha256 = '',
  });

  /// Показывать ли прямо в ленте.
  ///
  /// По типу содержимого, а не по расширению имени: файл `отчёт.jpg`,
  /// который на самом деле не картинка, иначе ронял бы отрисовку ленты.
  bool get isImage => mime.startsWith('image/');

  /// Есть ли сам файл на этом устройстве.
  bool get isHere => path.isNotEmpty;

  /// Размер словами. Байты в переписке никому ни о чём не говорят.
  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} КБ';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Map<String, String> toMap() => {
        'name': name,
        'path': path,
        'size': '$sizeBytes',
        'mime': mime,
        'sha256': sha256,
      };

  /// null — описание не разобралось. Такое сообщение покажется без
  /// вложения, но покажется: потерять текст из-за битого описания файла
  /// хуже, чем потерять описание.
  static ChatAttachment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    return ChatAttachment(
      name: name,
      path: '${raw['path'] ?? ''}',
      sizeBytes: int.tryParse('${raw['size'] ?? 0}') ?? 0,
      mime: '${raw['mime'] ?? 'application/octet-stream'}',
      sha256: '${raw['sha256'] ?? ''}',
    );
  }

  ChatAttachment withPath(String value) => ChatAttachment(
        name: name,
        path: value,
        sizeBytes: sizeBytes,
        mime: mime,
        sha256: sha256,
      );

  /// Тип содержимого по имени файла.
  ///
  /// Грубо и намеренно: полный разбор форматов здесь не нужен, нужно лишь
  /// решить, показывать картинку или карточку.
  static String mimeOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'doc' || 'docx' => 'application/msword',
      'xls' || 'xlsx' => 'application/vnd.ms-excel',
      'zip' => 'application/zip',
      'txt' => 'text/plain',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'mp4' || 'mov' => 'video/mp4',
      _ => 'application/octet-stream',
    };
  }
}
