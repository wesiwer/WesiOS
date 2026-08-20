enum WesiAiActivityKind {
  reasoning,
  tool,
  agent,
  status,
  verification,
}

class WesiAiActivityEvent {
  final String id;
  final WesiAiActivityKind kind;
  final String label;
  final String detail;
  final String status;
  final int textOffset;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int additions;
  final int deletions;
  final List<String> files;
  final String sourceName;

  /// Что ушло в инструмент и что он вернул.
  ///
  /// Без этого длинный проход нельзя проверить: человек видит два десятка
  /// строк «инструмент отработал» и обязан верить им на слово. Сервер держит
  /// защитный предел, но детальный слой сохраняет достаточно места для кода,
  /// аргументов и фактического результата инструмента.
  final String input;
  final String output;

  /// Шаг изменил данные WesiOS, а не только прочитал их, и изменение удалось.
  ///
  /// Признак приходит из реестра прав вместе с результатом инструмента. По
  /// нему собирается итог прохода: за двадцать шагов человеку важно не то,
  /// сколько раз ассистент что-то посмотрел, а что он поменял.
  final bool mutation;
  final bool succeeded;
  final String module;

  const WesiAiActivityEvent({
    required this.id,
    required this.kind,
    required this.label,
    this.detail = '',
    this.status = '',
    this.textOffset = 0,
    this.startedAt,
    this.completedAt,
    this.additions = 0,
    this.deletions = 0,
    this.files = const <String>[],
    this.sourceName = '',
    this.input = '',
    this.output = '',
    this.mutation = false,
    this.succeeded = false,
    this.module = '',
  });

  /// Изменение, которое действительно применилось.
  bool get appliedChange => mutation && succeeded;

  bool get hasIo => input.isNotEmpty || output.isNotEmpty;

  bool get hasDiff => additions > 0 || deletions > 0 || files.isNotEmpty;

  Duration? get duration {
    final start = startedAt;
    final end = completedAt;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  WesiAiActivityEvent copyWith({
    String? label,
    String? detail,
    String? status,
    int? textOffset,
    DateTime? startedAt,
    DateTime? completedAt,
    int? additions,
    int? deletions,
    List<String>? files,
    String? sourceName,
    String? input,
    String? output,
    bool? mutation,
    bool? succeeded,
    String? module,
  }) =>
      WesiAiActivityEvent(
        id: id,
        kind: kind,
        label: label ?? this.label,
        detail: detail ?? this.detail,
        status: status ?? this.status,
        textOffset: textOffset ?? this.textOffset,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        additions: additions ?? this.additions,
        deletions: deletions ?? this.deletions,
        files: files ?? this.files,
        sourceName: sourceName ?? this.sourceName,
        input: input ?? this.input,
        output: output ?? this.output,
        mutation: mutation ?? this.mutation,
        succeeded: succeeded ?? this.succeeded,
        module: module ?? this.module,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'label': label,
        if (detail.isNotEmpty) 'detail': detail,
        if (status.isNotEmpty) 'status': status,
        'textOffset': textOffset,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'additions': additions,
        'deletions': deletions,
        if (files.isNotEmpty) 'files': files,
        if (sourceName.isNotEmpty) 'sourceName': sourceName,
        if (input.isNotEmpty) 'input': input,
        if (output.isNotEmpty) 'output': output,
        if (mutation) 'mutation': true,
        if (succeeded) 'ok': true,
        if (module.isNotEmpty) 'module': module,
      };

  static WesiAiActivityEvent? fromJson(dynamic raw, {int fallbackIndex = 0}) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final rawKind =
        '${map['kind'] ?? map['type'] ?? 'status'}'.trim().toLowerCase();
    final phase = '${map['phase'] ?? ''}'.trim().toLowerCase();
    final kind = switch (rawKind) {
      'tool' => WesiAiActivityKind.tool,
      // Dynamic-subagent tool events travel over the shared `agent` envelope
      // so the lead can keep ownership of the run. Visually they are still
      // tool work: the second level must show tool input/code and tool result,
      // not mislabel the payload as another specialist assignment.
      'agent' when phase == 'tool' => WesiAiActivityKind.tool,
      'agent' => WesiAiActivityKind.agent,
      'reasoning' ||
      'reasoning_summary' ||
      'work' =>
        WesiAiActivityKind.reasoning,
      'verification' || 'verify' => WesiAiActivityKind.verification,
      _ => WesiAiActivityKind.status,
    };
    final sourceName = _clip(
        '${map['sourceName'] ?? map['name'] ?? map['tool'] ?? map['agent'] ?? map['persona'] ?? ''}',
        180);
    final explicitLabel = _clip('${map['label'] ?? map['title'] ?? ''}', 240);
    final label = explicitLabel.isNotEmpty
        ? explicitLabel
        : switch (kind) {
            WesiAiActivityKind.tool => sourceName.isEmpty
                ? 'Инструмент'
                : phase == 'result'
                    ? 'Инструмент · $sourceName'
                    : 'Запущен инструмент · $sourceName',
            WesiAiActivityKind.agent => sourceName.isEmpty
                ? 'Агент'
                : phase == 'result'
                    ? 'Агент завершил работу · $sourceName'
                    : 'Подключён агент · $sourceName',
            WesiAiActivityKind.reasoning => 'Ход работы',
            WesiAiActivityKind.verification => 'Проверка результата',
            WesiAiActivityKind.status =>
              sourceName.isEmpty ? 'Этап работы' : 'Маршрут · $sourceName',
          };
    final detail = _clip(
      '${map['detail'] ?? map['message'] ?? map['summary'] ?? map['code'] ?? ''}',
      12000,
    );
    final status = _clip('${map['status'] ?? map['phase'] ?? ''}', 80);
    final additions = _nonNegativeInt(
      map['additions'] ??
          _nested(map, 'diff', 'additions') ??
          _nested(map, 'stats', 'additions'),
    );
    final deletions = _nonNegativeInt(
      map['deletions'] ??
          _nested(map, 'diff', 'deletions') ??
          _nested(map, 'stats', 'deletions'),
    );
    final filesRaw = map['files'] ??
        _nested(map, 'diff', 'files') ??
        _nested(map, 'stats', 'files');
    final files = <String>[];
    if (filesRaw is List) {
      for (final item in filesRaw.take(40)) {
        final value = item is Map
            ? '${item['path'] ?? item['filename'] ?? item['name'] ?? ''}'
            : '$item';
        final clean = _clip(value, 500);
        if (clean.isNotEmpty && !files.contains(clean)) files.add(clean);
      }
    }
    final offset =
        _nonNegativeInt(map['textOffset']).clamp(0, 10000000).toInt();
    final startedAt = _date(map['startedAt'] ?? map['at']);
    final completedAt = _date(map['completedAt'] ?? map['finishedAt']);
    final id = _clip('${map['id'] ?? ''}', 180);
    // Совпадает с серверным пределом step_io: глубокий уровень должен уметь
    // показать код/аргументы целиком в пределах одного безопасного события.
    final input = _clip('${map['input'] ?? ''}', 24000);
    final output = _clip('${map['output'] ?? ''}', 24000);
    final mutation = map['mutation'] == true;
    final succeeded = map['ok'] == true;
    final module = _clip('${map['module'] ?? ''}', 60);
    return WesiAiActivityEvent(
      id: id.isEmpty ? 'activity_$fallbackIndex' : id,
      kind: kind,
      label: label,
      detail: detail,
      status: status,
      textOffset: offset,
      startedAt: startedAt,
      completedAt: completedAt,
      additions: additions,
      deletions: deletions,
      files: files,
      sourceName: sourceName,
      input: input,
      output: output,
      mutation: mutation,
      succeeded: succeeded,
      module: module,
    );
  }

  static List<WesiAiActivityEvent> listFrom(dynamic raw) {
    if (raw is! List) return const <WesiAiActivityEvent>[];
    final result = <WesiAiActivityEvent>[];
    // Длинный проход может законно содержать десятки инструментов и живых
    // публичных заметок между ними. Старые 120 событий обрезали хвост именно
    // тогда, когда пользователю важнее всего видеть продолжение работы.
    for (var index = 0; index < raw.length && index < 400; index++) {
      final event = fromJson(raw[index], fallbackIndex: index);
      if (event != null) result.add(event);
    }
    result.sort((a, b) {
      final byOffset = a.textOffset.compareTo(b.textOffset);
      if (byOffset != 0) return byOffset;
      final aTime = a.startedAt?.microsecondsSinceEpoch ?? 0;
      final bTime = b.startedAt?.microsecondsSinceEpoch ?? 0;
      return aTime.compareTo(bTime);
    });
    return result;
  }

  static int totalAdditions(Iterable<WesiAiActivityEvent> events) =>
      events.fold<int>(0, (total, event) => total + event.additions);

  static int totalDeletions(Iterable<WesiAiActivityEvent> events) =>
      events.fold<int>(0, (total, event) => total + event.deletions);

  static Object? _nested(
      Map<String, dynamic> map, String parent, String child) {
    final value = map[parent];
    if (value is! Map) return null;
    return value[child];
  }

  static int _nonNegativeInt(Object? value) {
    final number = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return number < 0 ? 0 : number;
  }

  static DateTime? _date(Object? value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static String _clip(String value, int max) {
    final clean = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .trim();
    return clean.length <= max ? clean : clean.substring(0, max);
  }
}
