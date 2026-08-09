import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/forecast_engine.dart';

/// Decision-first presentation for Wesi Horizon.
///
/// The chart remains useful, but this panel answers the actual cash-management
/// questions: how long cash lasts, when gap risk crosses material thresholds,
/// how much liquidity must be reserved, what is truly free, which scenario is
/// dangerous, and why the curve bends.
class HorizonDecisionPanel extends StatelessWidget {
  final ForecastResult forecast;

  const HorizonDecisionPanel({super.key, required this.forecast});

  bool get _ru => WesiLocale.isRussian;

  @override
  Widget build(BuildContext context) {
    if (forecast.p50.isEmpty) return const SizedBox.shrink();

    final confidenceColor = switch (forecast.confidence) {
      ForecastConfidence.high => AppTheme.accentGreen,
      ForecastConfidence.medium => AppTheme.accent,
      ForecastConfidence.low => Colors.amber,
      ForecastConfidence.insufficient => AppTheme.accentRed,
    };
    final horizon = forecast.p50.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 19, color: AppTheme.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _ru ? 'Решение Wesi Horizon' : 'Wesi Horizon decision',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              _chip(_confidenceLabel(), confidenceColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _confidenceExplanation(),
            style: TextStyle(
              color: AppTheme.textSecondary,
              height: 1.35,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 900
                  ? 3
                  : width >= 560
                      ? 2
                      : 1;
              final gap = 8.0;
              final itemWidth = (width - gap * (columns - 1)) / columns;
              final metrics = <Widget>[
                _metric(
                  _ru ? 'Медианный runway' : 'Median runway',
                  forecast.runwayDays == null
                      ? (_ru ? '>$horizon дн.' : '>$horizon d')
                      : (_ru
                          ? '${forecast.runwayDays} дн.'
                          : '${forecast.runwayDays} d'),
                  Icons.timelapse,
                ),
                _metric(
                  _ru ? 'Риск >10%' : 'Risk >10%',
                  _dayOrSafe(forecast.risk10Day, horizon),
                  Icons.warning_amber_rounded,
                ),
                _metric(
                  _ru ? 'Риск >25%' : 'Risk >25%',
                  _dayOrSafe(forecast.risk25Day, horizon),
                  Icons.crisis_alert,
                ),
                _metric(
                  _ru ? 'Рекомендуемая подушка' : 'Recommended reserve',
                  CurrencyService.formatExactSmart(forecast.recommendedReserve),
                  Icons.savings_outlined,
                ),
                _metric(
                  _ru ? 'Свободный буфер' : 'Free safety buffer',
                  CurrencyService.formatExactSmart(forecast.safetyBuffer),
                  Icons.account_balance_wallet_outlined,
                  valueColor: forecast.safetyBuffer < 0
                      ? AppTheme.accentRed
                      : AppTheme.accentGreen,
                ),
                _metric(
                  _ru ? 'Обязательства ≤30 дн.' : 'Committed ≤30d',
                  CurrencyService.formatExactSmart(forecast.committedNearTerm),
                  Icons.event_repeat,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(width: itemWidth, child: metric),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _progress(
                  _ru ? 'Известные деньги' : 'Known cash',
                  forecast.knownCashShare,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _progress(
                  _ru ? 'Калибровка P10–P90' : 'P10–P90 coverage',
                  forecast.calibrationCoverage,
                  target: .8,
                ),
              ),
            ],
          ),
          if (forecast.scenarioSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(
              _ru
                  ? 'Base / Conservative / Aggressive / Stress'
                  : 'Base / Conservative / Aggressive / Stress',
              Icons.account_tree_outlined,
            ),
            const SizedBox(height: 7),
            for (final scenario in forecast.scenarioSummaries)
              _scenarioRow(scenario),
          ],
          if (forecast.whatIfRiskDelta case final delta?) ...[
            const SizedBox(height: 14),
            _whatIfDelta(delta),
          ],
          if (forecast.actionPrompts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(
              _ru ? 'Что делать' : 'Actions',
              Icons.bolt_outlined,
            ),
            const SizedBox(height: 6),
            for (final prompt in forecast.actionPrompts.take(6))
              _prompt(prompt),
          ],
          if (forecast.accountLiquidityRisks.any((e) => e.riskDay != null)) ...[
            const SizedBox(height: 16),
            _sectionTitle(
              _ru ? 'Ликвидность по счетам' : 'Liquidity by account',
              Icons.account_balance_outlined,
            ),
            const SizedBox(height: 6),
            for (final risk in forecast.accountLiquidityRisks
                .where((e) => e.riskDay != null))
              _accountRisk(risk),
          ],
          if (forecast.explanations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(
              _ru ? 'Почему линия меняется' : 'Why the curve bends',
              Icons.lightbulb_outline,
            ),
            const SizedBox(height: 6),
            for (final explanation in forecast.explanations.take(8))
              _explanation(explanation),
          ],
        ],
      ),
    );
  }

  String _confidenceLabel() => switch (forecast.confidence) {
        ForecastConfidence.high =>
          _ru ? 'Высокая уверенность' : 'High confidence',
        ForecastConfidence.medium =>
          _ru ? 'Средняя уверенность' : 'Medium confidence',
        ForecastConfidence.low => _ru ? 'Низкая уверенность' : 'Low confidence',
        ForecastConfidence.insufficient =>
          _ru ? 'Недостаточно данных' : 'Insufficient data',
      };

  String _confidenceExplanation() {
    final known = (forecast.knownCashShare * 100).clamp(0, 100).round();
    return switch (forecast.confidence) {
      ForecastConfidence.high => _ru
          ? 'Истории достаточно для устойчивой оценки. Около $known% будущего денежного движения относится к известной части; остальное остаётся вероятностным.'
          : 'History is sufficient for a stable estimate. About $known% of future cash movement is known; the rest remains probabilistic.',
      ForecastConfidence.medium => _ru
          ? 'Прогноз пригоден для планирования, но дальний коридор намеренно расширяется. Не считай P50 обещанием точного баланса.'
          : 'Useful for planning, but long-range bands intentionally widen. P50 is not a promised balance.',
      ForecastConfidence.low => _ru
          ? 'Данных мало — Horizon честно не знает дальний баланс точно. Используй ближайшие недели, Stress и подушку, а не одну линию P50.'
          : 'Data is limited — Horizon does not pretend to know the distant balance precisely. Use the near term, Stress and reserve rather than P50 alone.',
      ForecastConfidence.insufficient => _ru
          ? 'Истории недостаточно для статистического прогноза.'
          : 'There is not enough history for a statistical forecast.',
    };
  }

  String _dayOrSafe(int? day, int horizon) {
    if (day == null) return _ru ? 'не выявлен' : 'not detected';
    return _ru ? '$day дн.' : '$day d';
  }

  Widget _metric(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withOpacity(.34),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.glassBorder.withOpacity(.75)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress(String label, double value, {double? target}) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    final display = '${(normalized * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
            ),
            Text(display,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: normalized,
            minHeight: 5,
            backgroundColor: AppTheme.surfaceLight,
            color: target == null || (normalized - target).abs() <= .12
                ? AppTheme.accent
                : Colors.amber,
          ),
        ),
      ],
    );
  }

  Widget _scenarioRow(ForecastScenarioSummary scenario) {
    final risk = (scenario.maximumGapRisk * 100).clamp(0, 100);
    final danger = risk >= 25 || scenario.minimumP10 < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              _ru ? scenario.labelRu : scenario.labelEn,
              style: TextStyle(
                color: scenario.key == 'stress'
                    ? AppTheme.accentRed
                    : AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'P50 ${CurrencyService.formatExactSmart(scenario.endingP50)}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 11.5),
            ),
          ),
          Text(
            '${_ru ? 'риск' : 'risk'} ${risk.toStringAsFixed(0)}%',
            style: TextStyle(
              color: danger ? AppTheme.accentRed : AppTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _whatIfDelta(WhatIfRiskDelta delta) {
    final diff = delta.riskDelta * 100;
    final worsened = diff > .5;
    final baseRunway = delta.baseRunwayDays;
    final scenarioRunway = delta.scenarioRunwayDays;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: (worsened ? AppTheme.accentRed : AppTheme.accentGreen)
            .withOpacity(.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: (worsened ? AppTheme.accentRed : AppTheme.accentGreen)
              .withOpacity(.3),
        ),
      ),
      child: Text(
        _ru
            ? 'What‑If: риск ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} п.п.; runway ${_runwayDelta(baseRunway, scenarioRunway)}.'
            : 'What‑If: risk ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} pp; runway ${_runwayDelta(baseRunway, scenarioRunway)}.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
      ),
    );
  }

  String _runwayDelta(int? base, int? scenario) {
    if (base == null && scenario == null) return _ru ? 'без разрыва' : 'no gap';
    if (base == null) return _ru ? '→ ${scenario!} дн.' : '→ ${scenario!} d';
    if (scenario == null) return _ru ? '$base → без разрыва' : '$base → no gap';
    final delta = scenario - base;
    return _ru
        ? '$base → $scenario дн. (${delta >= 0 ? '+' : ''}$delta)'
        : '$base → $scenario d (${delta >= 0 ? '+' : ''}$delta)';
  }

  Widget _prompt(ForecastActionPrompt prompt) {
    final color = switch (prompt.severity) {
      ForecastPromptSeverity.info => AppTheme.accent,
      ForecastPromptSeverity.warning => Colors.amber,
      ForecastPromptSeverity.critical => AppTheme.accentRed,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              _ru ? prompt.textRu : prompt.textEn,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRisk(AccountLiquidityRisk risk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 15, color: AppTheme.accentRed),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${risk.name} · ${risk.currency.toUpperCase()} · '
              '${_ru ? 'риск на ${risk.riskDay} дн.' : 'risk on day ${risk.riskDay}'}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
            ),
          ),
          _chip(
            risk.canBeCoveredByNetting
                ? (_ru ? 'можно перекрыть' : 'nettable')
                : (_ru ? 'локальный дефицит' : 'local shortfall'),
            risk.canBeCoveredByNetting
                ? AppTheme.accentGreen
                : AppTheme.accentRed,
          ),
        ],
      ),
    );
  }

  Widget _explanation(ForecastExplanation explanation) {
    final sign = explanation.impact >= 0 ? '+' : '−';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              _ru ? '${explanation.day} дн.' : 'd${explanation.day}',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
            ),
          ),
          Expanded(
            child: Text(
              _ru ? explanation.titleRu : explanation.titleEn,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$sign${CurrencyService.formatExactSmart(explanation.impact.abs())}',
            style: TextStyle(
              color: explanation.impact >= 0
                  ? AppTheme.accentGreen
                  : AppTheme.accentRed,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(.35)),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
        ),
      );
}
