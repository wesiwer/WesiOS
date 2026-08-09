import 'dart:math';

import '../models/transaction_model.dart';
import 'forecast_engine.dart';

class HorizonExplainabilityService {
  HorizonExplainabilityService._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Attribution of material P50 movements.
  ///
  /// This is deliberately additive: known event + other committed cash +
  /// uncertain operating center + quantile/remainder = observed P50 daily
  /// movement. The remainder is not hidden; Monte-Carlo non-linearity and
  /// calibration are named explicitly instead of inventing a fake cause.
  static List<ForecastExplanation> build({
    required ForecastResult forecast,
    required List<TransactionModel> transactions,
    List<HorizonCashEvent> businessEvents = const [],
    DateTime? now,
  }) {
    if (forecast.p50.isEmpty) return forecast.explanations;
    final today = _day(now ?? DateTime.now());
    final result = <ForecastExplanation>[];

    final dailyChanges = <double>[];
    for (var i = 0; i < forecast.p50.length; i++) {
      final previous = i == 0 ? null : forecast.p50[i - 1];
      if (previous != null) dailyChanges.add((forecast.p50[i] - previous).abs());
    }
    dailyChanges.sort();
    final typicalChange = dailyChanges.isEmpty
        ? forecast.dailyVolatility
        : dailyChanges[dailyChanges.length ~/ 2];
    final threshold = max(
      50.0,
      max(forecast.dailyVolatility * 0.40, typicalChange * 1.65),
    );

    final eventsByDay = <int, List<({String title, String source, double impact})>>{};
    for (final event in businessEvents) {
      final offset = _day(event.date).difference(today).inDays;
      if (offset < 1 || offset > forecast.p50.length) continue;
      (eventsByDay[offset] ??= []).add((
        title: event.title,
        source: event.source,
        impact: event.amount * event.probability,
      ));
    }
    for (final tx in transactions) {
      if (tx.isRecurring) continue;
      final offset = _day(tx.date).difference(today).inDays;
      if (offset < 1 || offset > forecast.p50.length) continue;
      (eventsByDay[offset] ??= []).add((
        title: tx.title,
        source: 'treasury-scheduled',
        impact: tx.type == TransactionType.income ? tx.amount : -tx.amount,
      ));
    }

    final dominantStreams = forecast.streamContribution.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final streamHint = dominantStreams.isEmpty
        ? ''
        : dominantStreams.take(2).map((e) => e.key).join(' + ');

    for (var i = 0; i < forecast.p50.length; i++) {
      final day = i + 1;
      final previous = i == 0 ? null : forecast.p50[i - 1];
      final delta = previous == null ? 0.0 : forecast.p50[i] - previous;
      final specificEvents = eventsByDay[day] ?? const [];
      final committed = forecast.committedNetByDay.length > i
          ? forecast.committedNetByDay[i]
          : 0.0;
      final uncertain = forecast.uncertainMedianByDay.length > i
          ? forecast.uncertainMedianByDay[i]
          : 0.0;
      final material = delta.abs() >= threshold ||
          specificEvents.isNotEmpty ||
          committed.abs() >= threshold;
      if (!material) continue;

      var eventTotal = 0.0;
      for (final event in specificEvents) {
        eventTotal += event.impact;
        result.add(ForecastExplanation(
          day: day,
          source: event.source,
          titleRu: 'Событие: ${event.title}',
          titleEn: 'Event: ${event.title}',
          impact: event.impact,
        ));
      }

      final committedRemainder = committed - eventTotal;
      if (committedRemainder.abs() >= max(10.0, threshold * 0.10)) {
        result.add(ForecastExplanation(
          day: day,
          source: 'committed-cash',
          titleRu: 'Прочие известные/регулярные обязательства',
          titleEn: 'Other known / recurring commitments',
          impact: committedRemainder,
        ));
      }

      if (uncertain.abs() >= max(10.0, threshold * 0.10)) {
        result.add(ForecastExplanation(
          day: day,
          source: 'operating-flow',
          titleRu: streamHint.isEmpty
              ? 'Ожидаемый нерегулярный денежный поток'
              : 'Операционный ритм: $streamHint',
          titleEn: streamHint.isEmpty
              ? 'Expected uncertain operating cash flow'
              : 'Operating rhythm: $streamHint',
          impact: uncertain,
        ));
      }

      final explainedCenter = committed + uncertain;
      final remainder = delta - explainedCenter;
      if (previous != null && remainder.abs() >= max(10.0, threshold * 0.10)) {
        result.add(ForecastExplanation(
          day: day,
          source: 'distribution-attribution',
          titleRu:
              'Режим, сезонность, шоки и quantile/calibration эффект P50',
          titleEn:
              'Regime, seasonality, shocks and quantile/calibration effect on P50',
          impact: remainder,
        ));
      }
    }

    // Keep model-native stress/regime explanations that are not already
    // represented by the additive decomposition.
    for (final explanation in forecast.explanations) {
      final duplicate = result.any((e) =>
          e.day == explanation.day &&
          e.source == explanation.source &&
          e.titleRu == explanation.titleRu);
      if (!duplicate) result.add(explanation);
    }
    result.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      return b.impact.abs().compareTo(a.impact.abs());
    });
    return result.take(80).toList();
  }
}
