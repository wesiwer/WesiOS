import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/transaction_model.dart';
import 'engine_install_service.dart';
import 'forecast_engine.dart';
import 'forecast_engine_kind.dart';

export 'forecast_engine_kind.dart';

/// Оценивает Cash Gap Risk Score по готовым P10/P50/P90, когда нет сырых
/// симулированных путей (Prophet/SARIMAX/Combined дают параметрический
/// доверительный интервал, не набор траекторий). Предполагает приблизительно
/// нормальное распределение вокруг P50: для нормального распределения
/// P10/P90 — это медиана ± 1.2816·σ, отсюда оценивается σ и вероятность
/// ухода в минус через функцию нормального распределения.
///
/// [ForecastEngine] (Wesi Horizon) в этом не нуждается — у него есть настоящие
/// пути симуляции, belowZeroProbability считается напрямую по ним и точнее.
class RiskEstimate {
  static const double _z80 = 1.2816; // z-квантиль для 90-го перцентиля

  static ({List<double> belowZero, int? runwayDays, int? riskAlertDay}) derive(
    List<double> p10,
    List<double> p50,
    List<double> p90, {
    double threshold = 0.05,
  }) {
    final belowZero = <double>[];
    int? runway;
    int? alert;
    // Коридор берём только там, где он есть на самом деле. Раньше цикл шёл
    // по длине p50 и читал p10[i]/p90[i] вслепую: движок, вернувший одну
    // медиану, ронял экран прогноза с RangeError.
    final hasBand = p10.length >= p50.length && p90.length >= p50.length;
    for (int i = 0; i < p50.length; i++) {
      final spread = hasBand ? (p90[i] - p10[i]).abs() : 0.0;
      final sigma = spread > 0 ? spread / (2 * _z80) : 0.0;
      final prob = sigma > 0
          ? _normalCdf(-p50[i] / sigma)
          : (p50[i] < 0 ? 1.0 : 0.0);
      belowZero.add(prob.clamp(0.0, 1.0));
      if (runway == null && p50[i] < 0) runway = i + 1;
      if (alert == null && prob > threshold) alert = i + 1;
    }
    return (belowZero: belowZero, runwayDays: runway, riskAlertDay: alert);
  }

  static double _normalCdf(double x) => 0.5 * (1 + _erf(x / sqrt2));

  /// Приближение Абрамовица-Стигана (7.1.26), максимальная погрешность ~1.5e-7
  /// — более чем достаточно для UI-индикатора риска, без новой зависимости.
  static double _erf(double x) {
    final sign = x < 0 ? -1.0 : 1.0;
    final ax = x.abs();
    const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
    const a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
    final t = 1.0 / (1.0 + p * ax);
    final y = 1.0 -
        (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-ax * ax);
    return sign * y;
  }
}

/// Мост к внешним движкам прогноза (Prophet, SARIMAX), реализованным как
/// отдельные Python-скрипты в `python_engines/`. Вызывается как подпроцесс —
/// намеренно fail-soft: если Python/скрипт/бандл не найден или упал, метод
/// возвращает null, а не бросает исключение. Экран прогноза показывает это
/// как «движок недоступен», а не падает и не показывает нули как реальные
/// данные.
///
/// В отличие от [ForecastEngine], здесь ОДИН ряд — чистый дневной денежный
/// поток (доход минус расход), не разделённый на потоки. Это стандартный
/// вход для Prophet/SARIMAX как библиотек, и общий контракт даёт честное
/// сравнение "движок против движка" на одних и тех же данных. Следствие:
/// сценарий «Что если?» к этим двум движкам не применяется.
class ExternalForecastBridge {
  static const Duration _timeout = Duration(seconds: 30);
  static const int _minHistoryDays = 14;

  static Future<ForecastResult?> run({
    required ForecastEngineKind engine,
    required List<TransactionModel> transactions,
    required double currentBalance,
    required int days,
  }) async {
    assert(engine == ForecastEngineKind.prophet ||
        engine == ForecastEngineKind.sarimax);

    final scriptFile = engine == ForecastEngineKind.prophet
        ? 'forecast_prophet.py'
        : 'forecast_sarimax.py';

    final python = await _resolvePython(engine);
    final script = await _resolveScript(engine, scriptFile);
    if (python == null || script == null) return null;

    final payload = _buildPayload(transactions, currentBalance, days);
    if (payload == null) return null; // недостаточно истории

    try {
      final process = await Process.start(python, [script]);
      process.stdin.write(jsonEncode(payload));
      await process.stdin.close();

      final stdout = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      await process.exitCode.timeout(const Duration(seconds: 5),
          onTimeout: () => -1);

      final lines = stdout.trim().split('\n');
      if (lines.isEmpty || lines.last.trim().isEmpty) return null;
      final decoded = jsonDecode(lines.last) as Map<String, dynamic>;
      if (decoded['error'] != null) return null;

      final p10 = _toDoubleList(decoded['p10']);
      final p50 = _toDoubleList(decoded['p50']);
      final p90 = _toDoubleList(decoded['p90']);
      if (p50.length != days) return null;
      // Коридор либо полный, либо его нет вовсе. Обрезок хуже отсутствия:
      // на графике он рисуется как настоящая полоса уверенности.
      final band = p10.length == days && p90.length == days;

      final risk = RiskEstimate.derive(p10, p50, p90);

      return ForecastResult(
        p10: band ? p10 : const [],
        p50: p50,
        p90: band ? p90 : const [],
        trendPerDay:
            p50.length >= 2 ? (p50.last - p50.first) / p50.length : 0,
        dailyVolatility: 0,
        historyDaysSpan: (decoded['history_days'] as num?)?.toInt() ?? 0,
        simulatedPaths: 0,
        insufficientData: false,
        seasonalityApplied: false,
        belowZeroProbability: risk.belowZero,
        runwayDays: risk.runwayDays,
        riskAlertDay: risk.riskAlertDay,
      );
    } catch (_) {
      return null;
    }
  }

  /// Список чисел из ответа движка.
  ///
  /// Ответ приходит из чужого процесса, и «нет ключа» или «там строка» —
  /// такой же возможный исход, как и нормальный JSON. Приведение `as List`
  /// на отсутствующем ключе роняло экран прогноза целиком.
  static List<double> _toDoubleList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <double>[];
    for (final e in raw) {
      if (e is num) {
        out.add(e.toDouble());
      } else {
        return const [];
      }
    }
    return out;
  }

  /// Порядок поиска: 1) движок, установленный через [EngineInstallService]
  /// (скачан по требованию пользователя в ApplicationSupportDirectory —
  /// основной путь после перехода на ленивую установку) → 2) старое место
  /// рядом с exe (оставлено на случай, если сборка когда-нибудь снова начнёт
  /// бандлить движок по умолчанию — не используется сейчас, но не мешает)
  /// → 3) системный Python (дев-фолбэк для локальной разработки).
  static Future<String?> _resolvePython(ForecastEngineKind engine) async {
    final installed = await EngineInstallService.pythonExecutable(engine);
    if (installed != null) return installed;

    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final bundled = '$exeDir\\python\\python.exe';
        if (await File(bundled).exists()) return bundled;
      } catch (_) {}
    }
    for (final candidate in ['python3', 'python']) {
      try {
        final probe = await Process.run(candidate, ['--version']);
        if (probe.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _resolveScript(
      ForecastEngineKind engine, String fileName) async {
    final installedDir = await EngineInstallService.scriptDirectory(engine);
    if (installedDir != null) {
      final path = '$installedDir${Platform.pathSeparator}$fileName';
      if (await File(path).exists()) return path;
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled =
          '$exeDir${Platform.pathSeparator}python_engines${Platform.pathSeparator}$fileName';
      if (await File(bundled).exists()) return bundled;
    } catch (_) {}
    final devPath = 'python_engines${Platform.pathSeparator}$fileName';
    if (await File(devPath).exists()) return devPath;
    return null;
  }

  /// Тот же плотный дневной ряд, что строит ForecastEngine внутри себя, но
  /// здесь — единый нетто (доход минус расход), включая регулярные платежи:
  /// Prophet/SARIMAX сами находят периодичность в истории, им не нужно
  /// (и нечем) отдельно проецировать регулярные события по датам.
  static Map<String, dynamic>? _buildPayload(
    List<TransactionModel> transactions,
    double currentBalance,
    int days,
  ) {
    if (transactions.isEmpty) return null;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    DateTime minDay = todayOnly;
    for (final tx in transactions) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = todayOnly.difference(minDay).inDays + 1;
    if (spanDays < _minHistoryDays) return null;

    final dense = List<double>.filled(spanDays, 0);
    for (final tx in transactions) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      final idx = day.difference(minDay).inDays;
      if (idx < 0 || idx >= spanDays) continue;
      dense[idx] += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    final history = List.generate(spanDays, (i) {
      final day = minDay.add(Duration(days: i));
      final y = day.year.toString().padLeft(4, '0');
      final m = day.month.toString().padLeft(2, '0');
      final d = day.day.toString().padLeft(2, '0');
      return {'date': '$y-$m-$d', 'net': dense[i]};
    });

    return {
      'history': history,
      'days': days,
      'current_balance': currentBalance,
    };
  }
}

/// Собирает «Комбинированный» прогноз — поэлементное среднее P10/P50/P90 по
/// тем движкам, что реально дали результат (недоступные/несчитавшиеся —
/// пропускаются, а не считаются нулём). Если ни один не досчитал — null.
ForecastResult? combineForecastResults(List<ForecastResult?> results) {
  final available = results
      .whereType<ForecastResult>()
      .where((r) => !r.insufficientData && r.p50.isNotEmpty)
      .toList();
  if (available.isEmpty) return null;

  final days = available.first.p50.length;
  if (available.any((r) => r.p50.length != days)) return null;
  // Усредняем коридор только по тем движкам, у которых он полный.
  final withBand = available
      .where((r) => r.p10.length == days && r.p90.length == days)
      .toList();

  double avgAt(List<double> Function(ForecastResult) select, int i) =>
      available.map((r) => select(r)[i]).reduce((a, b) => a + b) /
      available.length;

  double avgBandAt(List<double> Function(ForecastResult) select, int i) =>
      withBand.map((r) => select(r)[i]).reduce((a, b) => a + b) /
      withBand.length;

  final p50 = List<double>.generate(days, (i) => avgAt((r) => r.p50, i));
  final p10 = withBand.isEmpty
      ? const <double>[]
      : List<double>.generate(days, (i) => avgBandAt((r) => r.p10, i));
  final p90 = withBand.isEmpty
      ? const <double>[]
      : List<double>.generate(days, (i) => avgBandAt((r) => r.p90, i));
  final risk = RiskEstimate.derive(p10, p50, p90);

  return ForecastResult(
    p10: p10,
    p50: p50,
    p90: p90,
    trendPerDay:
        available.map((r) => r.trendPerDay).reduce((a, b) => a + b) /
            available.length,
    dailyVolatility:
        available.map((r) => r.dailyVolatility).reduce((a, b) => a + b) /
            available.length,
    historyDaysSpan:
        available.map((r) => r.historyDaysSpan).reduce((a, b) => a > b ? a : b),
    simulatedPaths: 0,
    insufficientData: false,
    seasonalityApplied: available.any((r) => r.seasonalityApplied),
    belowZeroProbability: risk.belowZero,
    runwayDays: risk.runwayDays,
    riskAlertDay: risk.riskAlertDay,
  );
}
