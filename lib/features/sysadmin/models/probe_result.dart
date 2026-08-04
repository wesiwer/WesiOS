/// Чем закончилась одна проверка.
enum ProbeOutcome {
  /// Ответил.
  up,

  /// Не ответил за отведённое время.
  timeout,

  /// Имя не разрешилось в адрес.
  dnsFailed,

  /// Адрес есть, но соединение отвергнуто — обычно порт закрыт.
  refused,

  /// Соединение установлено, но ответ не тот, которого ждали (для HTTP —
  /// код 4xx/5xx).
  badResponse,

  /// Ошибка сертификата.
  tlsFailed,

  /// У самого устройства нет сети. Это **не** то же самое, что «сервер
  /// упал», и валить их в одну кучу — верный способ поднимать на ноги
  /// работающий сервер.
  offline,
}

/// Один замер.
class ProbeSample {
  final DateTime at;
  final ProbeOutcome outcome;

  /// Время ответа. null, если ответа не было.
  final Duration? latency;

  /// Подробность для человека: код HTTP, текст ошибки.
  final String? detail;

  const ProbeSample({
    required this.at,
    required this.outcome,
    this.latency,
    this.detail,
  });

  bool get ok => outcome == ProbeOutcome.up;

  double? get ms => latency?.inMicroseconds == null
      ? null
      : latency!.inMicroseconds / 1000.0;

  String describe({bool russian = true}) {
    if (!russian) return _describeEn();
    return switch (outcome) {
      ProbeOutcome.up => 'Отвечает',
      ProbeOutcome.timeout => 'Не ответил вовремя',
      ProbeOutcome.dnsFailed => 'Имя не разрешается в адрес',
      ProbeOutcome.refused => 'Соединение отвергнуто — порт закрыт',
      ProbeOutcome.badResponse => detail ?? 'Ответ не тот',
      ProbeOutcome.tlsFailed => detail ?? 'Сертификат не принят',
      ProbeOutcome.offline => 'Нет сети на этом устройстве',
    };
  }

  String _describeEn() => switch (outcome) {
        ProbeOutcome.up => 'Responding',
        ProbeOutcome.timeout => 'Timed out',
        ProbeOutcome.dnsFailed => 'Name does not resolve',
        ProbeOutcome.refused => 'Connection refused — port closed',
        ProbeOutcome.badResponse => detail ?? 'Unexpected response',
        ProbeOutcome.tlsFailed => detail ?? 'Certificate rejected',
        ProbeOutcome.offline => 'This device is offline',
      };
}

/// Как оценивается состояние по накопленным замерам.
enum HealthGrade {
  /// Данных пока нет.
  unknown,

  /// Отвечает быстро и стабильно.
  good,

  /// Отвечает, но медленно или с потерями.
  degraded,

  /// Не отвечает.
  down,

  /// Проверить нельзя — нет сети у самого устройства.
  offline,
}

/// Сводка по окну замеров.
///
/// Считается отдельно от того, кто и как замеряет: правила оценки должны быть
/// видны целиком в одном месте и проверяться тестами, а не выясняться по
/// цветной точке на экране.
class ProbeStats {
  final List<ProbeSample> samples;

  const ProbeStats(this.samples);

  static const ProbeStats empty = ProbeStats([]);

  List<ProbeSample> get _answered => [
        for (final s in samples)
          if (s.ok && s.latency != null) s,
      ];

  bool get isEmpty => samples.isEmpty;

  int get total => samples.length;

  int get lost => samples.where((s) => !s.ok).length;

  /// Доля потерь, 0..1.
  double get loss => samples.isEmpty ? 0 : lost / samples.length;

  double? get minMs {
    final a = _answered;
    if (a.isEmpty) return null;
    return a.map((s) => s.ms!).reduce((x, y) => x < y ? x : y);
  }

  double? get maxMs {
    final a = _answered;
    if (a.isEmpty) return null;
    return a.map((s) => s.ms!).reduce((x, y) => x > y ? x : y);
  }

  double? get avgMs {
    final a = _answered;
    if (a.isEmpty) return null;
    return a.map((s) => s.ms!).reduce((x, y) => x + y) / a.length;
  }

  /// Разброс времени ответа — среднее отклонение между соседними замерами.
  ///
  /// Именно между соседними, а не от среднего: связь, где ответ то 20 мс, то
  /// 200, ощущается рывками, даже если среднее приличное. Стандартное
  /// отклонение такую картину сглаживает и прячет.
  double? get jitterMs {
    final a = _answered;
    if (a.length < 2) return null;
    var sum = 0.0;
    for (var i = 1; i < a.length; i++) {
      sum += (a[i].ms! - a[i - 1].ms!).abs();
    }
    return sum / (a.length - 1);
  }

  ProbeSample? get last => samples.isEmpty ? null : samples.last;

  /// Оценка состояния.
  ///
  /// Пороги подобраны под задачу «сервер жив и им можно пользоваться», а не
  /// под соревнование по скорости: 300 мс до сервера в другой стране —
  /// нормально, а вот потеря каждого десятого ответа означает, что связь
  /// рвётся.
  HealthGrade get grade {
    if (samples.isEmpty) return HealthGrade.unknown;
    if (samples.last.outcome == ProbeOutcome.offline) return HealthGrade.offline;

    // Оцениваем по хвосту окна, а не по всему: сервер, полчаса назад
    // лежавший и уже поднявшийся, должен показывать «работает».
    final tail = samples.length <= 5
        ? samples
        : samples.sublist(samples.length - 5);
    final aliveInTail = tail.where((s) => s.ok).length;
    if (aliveInTail == 0) return HealthGrade.down;

    if (loss >= 0.1) return HealthGrade.degraded;
    final avg = avgMs;
    if (avg != null && avg >= 1000) return HealthGrade.degraded;
    final jitter = jitterMs;
    if (jitter != null && jitter >= 250) return HealthGrade.degraded;
    return HealthGrade.good;
  }
}

/// Что известно про сертификат домена.
class TlsInfo {
  final String subject;
  final String issuer;
  final DateTime validUntil;

  const TlsInfo({
    required this.subject,
    required this.issuer,
    required this.validUntil,
  });

  int daysLeft(DateTime now) => validUntil.difference(now).inDays;

  /// Пора беспокоиться.
  ///
  /// Let's Encrypt выдаёт сертификат на 90 дней и обновляет за 30 до конца.
  /// Если осталось меньше двух недель — обновление не сработало, и это надо
  /// увидеть заранее, а не в день, когда сайт перестанет открываться.
  bool expiringSoon(DateTime now) => daysLeft(now) <= 14;

  bool expired(DateTime now) => !validUntil.isAfter(now);
}
