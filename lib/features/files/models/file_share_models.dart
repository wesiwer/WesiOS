/// Обмен файлами между устройствами команды.
///
/// Файлы битов и документы сотрудников слишком велики для обычной
/// синхронизации: mp3 и wav — десятки и сотни мегабайт, а запись на сервере
/// ограничена двумя. Поэтому в обмене ходит только описание («у кого что
/// есть»), а сам файл передаётся напрямую по запросу и с подтверждением
/// владельца.
///
/// Здесь описано, **кто кому что может отдать** и **что уже отдали**. Сама
/// передача — отдельно: правила должны быть проверяемы без сети, а сеть
/// заменяема без правки правил.
library;

/// Что именно раздаётся.
///
/// Разделение не косметическое: у документов сотрудника правила строже, и
/// перепутать их с битом нельзя ни при каких условиях.
enum ShareSubjectKind {
  /// Файл бита из аудио-хранилища.
  beat,

  /// Документ сотрудника: договор, соглашение, скан.
  employeeDocument,
}

/// Какой из файлов записи запрашивают.
enum ShareFileKind { mp3, wav, trackout, cover, attachment, document }

/// Состояние запроса.
enum ShareRequestStatus {
  /// Отправлен, владелец ещё не ответил.
  pending,

  /// Владелец согласился, передача не завершена.
  approved,

  /// Владелец отказал.
  declined,

  /// Файл дошёл до запросившего.
  delivered,

  /// Запросивший передумал.
  cancelled,

  /// Никто не ответил в отведённый срок.
  expired,
}

/// Открытый доступ к файлам одной записи.
///
/// Право на раздел даёт видеть каталог, но не получать файлы: увидеть, что
/// бит существует, и унести его wav — разные вещи, и для второго нужно
/// отдельное разрешение.
class FileAccessGrant {
  final String id;
  final ShareSubjectKind subjectKind;

  /// Идентификатор бита или сотрудника, чьи это документы.
  final String subjectId;

  /// Кому открыт доступ.
  final String employeeId;

  final String grantedBy;
  final DateTime grantedAt;

  /// Срок. `null` — бессрочно.
  ///
  /// Временный доступ нужен там, где бит отдают на сведение или на прослушку:
  /// разрешение, которое надо не забыть отозвать, отзывают редко.
  final DateTime? expiresAt;

  /// Может ли он сам раздавать этот файл дальше.
  ///
  /// По умолчанию нет: получить бит и стать его распространителем — разные
  /// решения, и второе принимает владелец, а не получатель.
  final bool canReshare;

  const FileAccessGrant({
    required this.id,
    required this.subjectKind,
    required this.subjectId,
    required this.employeeId,
    required this.grantedBy,
    required this.grantedAt,
    this.expiresAt,
    this.canReshare = false,
  });

  bool isActiveAt(DateTime moment) =>
      expiresAt == null || expiresAt!.isAfter(moment);

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectKind': subjectKind.name,
        'subjectId': subjectId,
        'employeeId': employeeId,
        'grantedBy': grantedBy,
        'grantedAt': grantedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'canReshare': canReshare,
      };

  static FileAccessGrant? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final subjectId = '${json['subjectId'] ?? ''}'.trim();
    final employeeId = '${json['employeeId'] ?? ''}'.trim();
    final grantedAt = DateTime.tryParse('${json['grantedAt'] ?? ''}');
    if (id.isEmpty || subjectId.isEmpty || employeeId.isEmpty ||
        grantedAt == null) {
      return null;
    }
    return FileAccessGrant(
      id: id,
      subjectKind: _kind(json['subjectKind']),
      subjectId: subjectId,
      employeeId: employeeId,
      grantedBy: '${json['grantedBy'] ?? ''}',
      grantedAt: grantedAt,
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
      canReshare: json['canReshare'] == true,
    );
  }
}

/// Просьба прислать файл.
class FileShareRequest {
  final String id;
  final ShareSubjectKind subjectKind;
  final String subjectId;
  final ShareFileKind fileKind;

  /// Для вложений — какое именно. Для остальных пусто.
  final String attachmentId;

  final String requesterId;

  /// У кого именно просят. Пусто — у любого, у кого файл есть.
  final String holderId;

  final ShareRequestStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String decidedBy;

  /// Почему отказали. Человеку важнее причина, чем факт отказа.
  final String declineReason;

  const FileShareRequest({
    required this.id,
    required this.subjectKind,
    required this.subjectId,
    required this.fileKind,
    required this.requesterId,
    required this.createdAt,
    this.attachmentId = '',
    this.holderId = '',
    this.status = ShareRequestStatus.pending,
    this.decidedAt,
    this.decidedBy = '',
    this.declineReason = '',
  });

  bool get isOpen =>
      status == ShareRequestStatus.pending ||
      status == ShareRequestStatus.approved;

  FileShareRequest copyWith({
    ShareRequestStatus? status,
    DateTime? decidedAt,
    String? decidedBy,
    String? declineReason,
  }) =>
      FileShareRequest(
        id: id,
        subjectKind: subjectKind,
        subjectId: subjectId,
        fileKind: fileKind,
        attachmentId: attachmentId,
        requesterId: requesterId,
        holderId: holderId,
        createdAt: createdAt,
        status: status ?? this.status,
        decidedAt: decidedAt ?? this.decidedAt,
        decidedBy: decidedBy ?? this.decidedBy,
        declineReason: declineReason ?? this.declineReason,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectKind': subjectKind.name,
        'subjectId': subjectId,
        'fileKind': fileKind.name,
        'attachmentId': attachmentId,
        'requesterId': requesterId,
        'holderId': holderId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'decidedAt': decidedAt?.toIso8601String(),
        'decidedBy': decidedBy,
        'declineReason': declineReason,
      };

  static FileShareRequest? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final subjectId = '${json['subjectId'] ?? ''}'.trim();
    final requesterId = '${json['requesterId'] ?? ''}'.trim();
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}');
    if (id.isEmpty || subjectId.isEmpty || requesterId.isEmpty ||
        createdAt == null) {
      return null;
    }
    return FileShareRequest(
      id: id,
      subjectKind: _kind(json['subjectKind']),
      subjectId: subjectId,
      fileKind: _fileKind(json['fileKind']),
      attachmentId: '${json['attachmentId'] ?? ''}',
      requesterId: requesterId,
      holderId: '${json['holderId'] ?? ''}',
      status: _status(json['status']),
      createdAt: createdAt,
      decidedAt: DateTime.tryParse('${json['decidedAt'] ?? ''}'),
      decidedBy: '${json['decidedBy'] ?? ''}',
      declineReason: '${json['declineReason'] ?? ''}',
    );
  }
}

/// Каким путём файл дошёл.
enum ShareRoute {
  /// Напрямую в одной сети — студия, офис.
  lan,

  /// Через сервер как перевалочный пункт.
  relay,

  /// Напрямую через интернет.
  peer,

  /// Файл принесли руками: флешка, мессенджер. Отмечается вручную, чтобы
  /// журнал оставался полным.
  manual,
}

/// Запись в журнале: что и кому реально отдали.
///
/// Для битов это не бухгалтерия ради бухгалтерии. Бит, сданный в
/// эксклюзивную аренду, — предмет договора, и вопрос «откуда у него wav»
/// однажды окажется важным. Отпечаток файла хранится, чтобы ответ на него не
/// зависел от чьей-то памяти.
class FileHandover {
  final String id;
  final ShareSubjectKind subjectKind;
  final String subjectId;
  final ShareFileKind fileKind;
  final String fromEmployeeId;
  final String toEmployeeId;
  final int sizeBytes;

  /// SHA-256 переданного файла.
  final String checksum;

  final DateTime at;
  final ShareRoute route;

  /// По какому запросу. Пусто, если файл отдали без запроса.
  final String requestId;

  const FileHandover({
    required this.id,
    required this.subjectKind,
    required this.subjectId,
    required this.fileKind,
    required this.fromEmployeeId,
    required this.toEmployeeId,
    required this.at,
    this.sizeBytes = 0,
    this.checksum = '',
    this.route = ShareRoute.lan,
    this.requestId = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectKind': subjectKind.name,
        'subjectId': subjectId,
        'fileKind': fileKind.name,
        'fromEmployeeId': fromEmployeeId,
        'toEmployeeId': toEmployeeId,
        'sizeBytes': sizeBytes,
        'checksum': checksum,
        'at': at.toIso8601String(),
        'route': route.name,
        'requestId': requestId,
      };

  static FileHandover? tryParse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final subjectId = '${json['subjectId'] ?? ''}'.trim();
    final at = DateTime.tryParse('${json['at'] ?? ''}');
    if (id.isEmpty || subjectId.isEmpty || at == null) return null;
    return FileHandover(
      id: id,
      subjectKind: _kind(json['subjectKind']),
      subjectId: subjectId,
      fileKind: _fileKind(json['fileKind']),
      fromEmployeeId: '${json['fromEmployeeId'] ?? ''}',
      toEmployeeId: '${json['toEmployeeId'] ?? ''}',
      sizeBytes: json['sizeBytes'] is num
          ? (json['sizeBytes'] as num).toInt()
          : 0,
      checksum: '${json['checksum'] ?? ''}',
      at: at,
      route: ShareRoute.values.firstWhere(
        (r) => r.name == '${json['route']}',
        orElse: () => ShareRoute.lan,
      ),
      requestId: '${json['requestId'] ?? ''}',
    );
  }
}

ShareSubjectKind _kind(Object? raw) => ShareSubjectKind.values.firstWhere(
      (k) => k.name == '$raw',
      orElse: () => ShareSubjectKind.beat,
    );

ShareFileKind _fileKind(Object? raw) => ShareFileKind.values.firstWhere(
      (k) => k.name == '$raw',
      orElse: () => ShareFileKind.mp3,
    );

ShareRequestStatus _status(Object? raw) => ShareRequestStatus.values.firstWhere(
      (s) => s.name == '$raw',
      // Незнакомое состояние — скорее всего от более новой версии. Считать
      // его выполненным нельзя: это открыло бы доступ, которого не давали.
      orElse: () => ShareRequestStatus.pending,
    );
