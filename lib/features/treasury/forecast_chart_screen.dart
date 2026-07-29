import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/widgets/currency_picker.dart';
import 'services/treasury_service.dart';
import 'services/forecast_engine.dart';
import 'services/multi_engine_forecast.dart';
import 'models/transaction_model.dart';
import 'widgets/what_if_dialog.dart';
import 'widgets/engine_install_banner.dart';

class TreasuryForecastScreen extends StatefulWidget {
  const TreasuryForecastScreen({super.key});

  @override
  State<TreasuryForecastScreen> createState() => _TreasuryForecastScreenState();
}

class _TreasuryForecastScreenState extends State<TreasuryForecastScreen> {
  final TreasuryService _service = TreasuryService();

  ForecastResult _forecast = ForecastResult.empty();
  List<ForecastPoint> _data = [];
  List<TransactionModel> _anomalies = [];
  Map<String, double> _categoryBreakdown = {};
  bool _isLoading = true;
  bool _chartBusy = false; // только график, не весь экран

  // Смысл каждого переключателя разведён однозначно:
  // — P10–P90 — пунктирные границы диапазона;
  // — доверительные интервалы — заливка между ними;
  // — линия тренда — медианная (P50) линия.
  bool _showP10P90 = true;
  bool _showConfidenceBands = true;
  bool _showTrendLine = true;
  int _forecastDays = 30;
  int _historyWindowDays = 30;
  DateTimeRange? _customRange;
  String _selectedChart = 'forecast';
  String _currency = CurrencyService.current;
  WhatIfScenario _whatIf = WhatIfScenario.none;
  bool _discountEnabled = false;

  /// Условная ставка дисконтирования (инфляция/стоимость денег) — применима
  /// только к длинным (от года) горизонтам, включается отдельным тоглом.
  static const double _annualDiscountRate = 0.08;

  // ===== Мульти-движковый прогноз: Wesi Horizon / Prophet / SARIMAX / Combined =====
  //
  // Wesi Horizon всегда доступен и пересчитывается в _loadData вместе со всем
  // остальным (это тот же _forecast). Prophet/SARIMAX — внешние Python-движки,
  // считаются ЛЕНИВО: только когда пользователь включает тумблер, и только
  // один раз до следующего изменения периода/сценария (см. _loadData).
  // Комбинированный не считается отдельно — это среднее по тем движкам,
  // что реально посчитались (см. combineForecastResults).
  final Set<ForecastEngineKind> _activeEngines = {ForecastEngineKind.wesiHorizon};
  final Map<ForecastEngineKind, ForecastResult?> _engineCache = {};
  final Set<ForecastEngineKind> _loadingEngines = {};
  final Set<ForecastEngineKind> _unavailableEngines = {};

  static const Map<ForecastEngineKind, Color> _engineColor = {
    ForecastEngineKind.wesiHorizon: AppTheme.accentOrange,
    ForecastEngineKind.prophet: Color(0xFF38BDF8),
    ForecastEngineKind.sarimax: Color(0xFFC084FC),
    ForecastEngineKind.combined: Color(0xFF2DD4BF),
  };

  /// Фон графика — сплошной цвет, каким контейнер реально рендерится
  /// (surface@0.4 поверх background). Нужен, чтобы «стереть» лишнюю заливку
  /// под P10 и получить полосу ровно между P10 и P90, а не до низа графика.
  static final Color _chartBg = Color.alphaBlend(
    AppTheme.surface.withOpacity(0.4),
    AppTheme.background,
  );

  @override
  void initState() {
    super.initState();
    _loadData(full: true);
  }

  Future<void> _loadData({bool full = false}) async {
    if (full) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _chartBusy = true);
    }

    final forecast = await _service.generateForecast(
      days: _forecastDays,
      whatIf: _whatIf,
      annualDiscountRate: _discountEnabled ? _annualDiscountRate : 0.0,
    );
    final txs = await _service.getAllTransactions();
    // detectAnomalies() возвращает копии с выставленным isAnomaly — этот флаг
    // никогда не пишется обратно в Hive, поэтому `txs`/`tx.isAnomaly` его не
    // содержит для реально обнаруженных (не «зашитых» в демо-данных) случаев.
    // Берём список отдельно, как это уже правильно делают Treasury/Sandbox.
    final anomalies = await _service.detectAnomalies();

    final breakdown = <String, double>{};
    for (final tx in txs) {
      final cat = tx.category ?? 'uncategorized'.w;
      breakdown[cat] = (breakdown[cat] ?? 0) +
          (tx.type == TransactionType.income ? tx.amount : -tx.amount);
    }

    // История на графике масштабируется вместе с горизонтом прогноза —
    // 90-дневный прогноз без контекста истории тяжелее оценить на глаз.
    final historyWindowDays = _forecastDays.clamp(30, 90);

    final data = <ForecastPoint>[];
    final now = DateTime.now();
    double runningBalance = 0;

    for (final tx in txs.where((t) =>
        t.date.isBefore(now.subtract(Duration(days: historyWindowDays))))) {
      runningBalance +=
          tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }

    for (int i = historyWindowDays; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayTxs = txs.where((t) =>
          t.date.year == day.year &&
          t.date.month == day.month &&
          t.date.day == day.day);
      double dayNet = 0;
      for (final tx in dayTxs) {
        dayNet += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      runningBalance += dayNet;
      // История — факт, а не оценка: p10/p50/p90 совпадают с фактическим
      // балансом (раньше здесь была фиктивная полоса ±3%, вводившая в
      // заблуждение — история не имеет доверительного интервала).
      data.add(ForecastPoint(
        day: historyWindowDays - i,
        p10: runningBalance,
        p50: runningBalance,
        p90: runningBalance,
        actual: runningBalance,
        isForecast: false,
      ));
    }

    for (int i = 0; i < forecast.p50.length; i++) {
      data.add(ForecastPoint(
        day: historyWindowDays + 1 + i,
        p10: forecast.p10.isNotEmpty ? forecast.p10[i] : forecast.p50[i],
        p50: forecast.p50[i],
        p90: forecast.p90.isNotEmpty ? forecast.p90[i] : forecast.p50[i],
        isForecast: true,
      ));
    }

    if (!mounted) return;
    setState(() {
      _forecast = forecast;
      _data = data;
      _anomalies = anomalies;
      _categoryBreakdown = breakdown;
      _historyWindowDays = historyWindowDays;
      _currency = CurrencyService.current;
      _isLoading = false;
      _chartBusy = false;

      // Период/сценарий поменялись — кэш внешних движков и комбинированного
      // устарел. Wesi Horizon пересчитан только что, он всегда актуален.
      _engineCache[ForecastEngineKind.wesiHorizon] = forecast;
      _engineCache.remove(ForecastEngineKind.prophet);
      _engineCache.remove(ForecastEngineKind.sarimax);
      _engineCache.remove(ForecastEngineKind.combined);
      _unavailableEngines.clear();
    });

    // Если Prophet/SARIMAX/Combined были включены — досчитать их заново под
    // новые данные. Не блокирует основной экран (лоадер уже снят выше).
    for (final kind in _activeEngines) {
      if (kind != ForecastEngineKind.wesiHorizon) _ensureEngineComputed(kind);
    }
  }

  /// Включает/выключает показ движка на графике/в таблице сравнения. Для
  /// Prophet/SARIMAX первое включение запускает ленивый расчёт (внешний
  /// Python-подпроцесс, может занять секунду-другую) — виден отдельный
  /// индикатор загрузки прямо на тумблере, не общий экран.
  Future<void> _toggleEngine(ForecastEngineKind kind) async {
    setState(() {
      if (_activeEngines.contains(kind)) {
        _activeEngines.remove(kind);
      } else {
        _activeEngines.add(kind);
      }
    });
    if (_activeEngines.contains(kind)) await _ensureEngineComputed(kind);
  }

  Future<void> _ensureEngineComputed(ForecastEngineKind kind) async {
    if (kind == ForecastEngineKind.wesiHorizon) return; // уже в кэше всегда
    if (kind == ForecastEngineKind.combined) {
      setState(_recomputeCombined);
      return;
    }
    if (_engineCache.containsKey(kind) || _loadingEngines.contains(kind)) {
      return;
    }
    setState(() => _loadingEngines.add(kind));
    final txs = await _service.getAllTransactions();
    final balance = await _service.getCurrentBalance();
    final result = await ExternalForecastBridge.run(
      engine: kind,
      transactions: txs,
      currentBalance: balance,
      days: _forecastDays,
    );
    if (!mounted) return;
    setState(() {
      _loadingEngines.remove(kind);
      _engineCache[kind] = result;
      if (result == null) {
        _unavailableEngines.add(kind);
      } else {
        _unavailableEngines.remove(kind);
      }
      _recomputeCombined();
    });
  }

  void _recomputeCombined() {
    _engineCache[ForecastEngineKind.combined] = combineForecastResults([
      _engineCache[ForecastEngineKind.wesiHorizon],
      _engineCache[ForecastEngineKind.prophet],
      _engineCache[ForecastEngineKind.sarimax],
    ]);
  }

  Future<void> _cycleCurrency() async {
    final picked = await CurrencyPicker.show(context);
    if (picked == null) return;
    await CurrencyService.set(picked);
    if (mounted) setState(() => _currency = picked);
  }

  void _changePeriod(int days) {
    final hadRange = _customRange != null;
    if (_forecastDays == days && !hadRange) return;
    setState(() {
      _forecastDays = days;
      _customRange = null;
    });
    _loadData(full: false); // без полноэкранного лоадера
  }

  /// Сценарий «Что если?» — виртуальный, ничего не пишет в базу. Пересчёт
  /// идёт через тот же _loadData, просто с новым параметром whatIf.
  Future<void> _openWhatIf() async {
    final result = await showDialog<WhatIfScenario>(
      context: context,
      builder: (context) => WhatIfDialog(
        initial: _whatIf,
        forecastDays: _forecastDays,
        symbol: CurrencyService.symbol,
      ),
    );
    if (result == null) return;
    setState(() => _whatIf = result);
    _loadData(full: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accentOrange.withOpacity(0.5)),
        ),
      );
    }

    if (_forecast.insufficientData) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text('wesi_forecast_title'.w),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.query_stats,
                    size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  'insufficient_data'.w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'insufficient_data_hint'.w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final forecastPoints = _data.where((d) => d.isForecast).toList();
    final last = forecastPoints.isNotEmpty ? forecastPoints.last : null;
    final first = forecastPoints.isNotEmpty ? forecastPoints.first : null;
    final growth = (last != null && first != null && first.p50 != 0)
        ? ((last.p50 - first.p50) / first.p50.abs() * 100)
        : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text('wesi_forecast_title'.w),
        actions: [
          IconButton(
            icon: Icon(Icons.alt_route,
                color: _whatIf.isEmpty ? null : AppTheme.accentOrange),
            tooltip: 'what_if'.w,
            onPressed: _openWhatIf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(full: false),
          ),
          const SizedBox(width: 120),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const EngineInstallBanner(),
          if (!_whatIf.isEmpty) _whatIfBanner(),
          _riskBanner(),
          Row(
            children: [
              Expanded(child: _stats(last, growth)),
              const SizedBox(width: 8),
              _currencyBadge(),
            ],
          ),
          const SizedBox(height: 8),
          _diagnostics(),
          const SizedBox(height: 12),
          _engineSelector(),
          const SizedBox(height: 12),
          _chartModeTabs(),
          const SizedBox(height: 10),
          _periodChips(),
          const SizedBox(height: 12),
          // График: плавная смена без сброса всего экрана
          AnimatedOpacity(
            opacity: _chartBusy ? 0.45 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: _chartForMode(),
          ),
          if (_selectedChart == 'forecast' && _activeEngines.length > 1) ...[
            const SizedBox(height: 10),
            _engineLegend(),
          ],
          if (_selectedChart == 'forecast') ...[
            const SizedBox(height: 20),
            _comparisonTable(),
          ],
          const SizedBox(height: 16),
          Text('display_options'.w,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          _controls(),
          const SizedBox(height: 24),
          if (_categoryBreakdown.isNotEmpty) _breakdown(),
          const SizedBox(height: 24),
          _anomaliesSection(),
        ],
      ),
    );
  }

  Widget _currencyBadge() {
    return GestureDetector(
      onTap: _cycleCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(
          '${CurrencyService.symbol} ${_currency.toUpperCase()}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentOrange,
          ),
        ),
      ),
    );
  }

  /// Явный индикатор виртуального сценария — чтобы нельзя было спутать
  /// гипотетические цифры с реальным прогнозом.
  Widget _whatIfBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accentOrange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alt_route, size: 18, color: AppTheme.accentOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text('what_if_active'.w,
                style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _whatIf = WhatIfScenario.none);
              _loadData(full: false);
            },
            child: Text('what_if_reset'.w,
                style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }

  /// Cash Gap Risk Score: предупреждение, если вероятность ухода баланса
  /// в минус в какой-то день прогноза превышает 5% симулированных путей.
  Widget _riskBanner() {
    final alertDay = _forecast.riskAlertDay;
    if (alertDay == null) return const SizedBox.shrink();
    final date = DateTime.now().add(Duration(days: alertDay));
    final dateLabel = '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('cash_gap_risk'.w,
                    style: const TextStyle(
                        color: AppTheme.accentRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'cash_gap_risk_detail'.w
                      .replaceAll('{days}', '$alertDay')
                      .replaceAll('{date}', dateLabel),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Прозрачность про то, на чём построен прогноз — сколько истории,
  /// сколько траекторий симулировано, учтена ли сезонность по дню недели.
  Widget _diagnostics() {
    final daysLabel =
        'based_on_history'.w.replaceAll('{days}', '${_forecast.historyDaysSpan}');
    final pathsLabel =
        'monte_carlo_paths'.w.replaceAll('{n}', '${_forecast.simulatedPaths}');
    final seasonLabel =
        _forecast.seasonalityApplied ? 'seasonality_on'.w : 'seasonality_off'.w;
    return Text(
      '$daysLabel · $pathsLabel · $seasonLabel',
      style: TextStyle(fontSize: 11, color: AppTheme.textMuted.withOpacity(0.8)),
    );
  }

  /// Переключатель движков прогноза: Wesi Horizon (родной), Prophet, SARIMAX
  /// — независимые тумблеры, можно включить любое подмножество (в т.ч. ни
  /// одного — тогда график и таблица пустые) или все сразу. «Комбинированный»
  /// — не отдельный расчёт, а среднее по тем, что реально посчитались.
  Widget _engineSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ForecastEngineKind.values.map((kind) {
        final active = _activeEngines.contains(kind);
        final loading = _loadingEngines.contains(kind);
        final unavailable = _unavailableEngines.contains(kind);
        final color = _engineColor[kind]!;
        final label = WesiLocale.isRussian ? kind.nameRu : kind.nameEn;

        Widget leading;
        if (loading) {
          leading = SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
          );
        } else if (unavailable) {
          leading = Icon(Icons.error_outline, size: 14, color: AppTheme.textMuted);
        } else {
          leading = Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : AppTheme.textMuted.withOpacity(0.4),
            ),
          );
        }

        final chip = GestureDetector(
          onTap: () => _toggleEngine(kind),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? color.withOpacity(0.15) : AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? color.withOpacity(0.5) : AppTheme.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: unavailable
                        ? AppTheme.textMuted
                        : (active ? color : AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );

        if (!unavailable) return chip;
        return Tooltip(
          message: 'engine_unavailable_hint'.w,
          child: chip,
        );
      }).toList(),
    );
  }

  Widget _engineLegend() {
    final active = ForecastEngineKind.values.where(_activeEngines.contains);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: active.map((kind) {
        final color = _engineColor[kind]!;
        final label = WesiLocale.isRussian ? kind.nameRu : kind.nameEn;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 3,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        );
      }).toList(),
    );
  }

  /// Таблица сравнения: по строке на выбранный день горизонта, по столбцу на
  /// активный движок (P50). Полный список дней при большом горизонте не
  /// поместится и не нужен — берём равномерную выборку точек.
  Widget _comparisonTable() {
    final active = ForecastEngineKind.values
        .where((k) => _activeEngines.contains(k) && _engineCache[k] != null)
        .toList();

    if (active.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text('no_engines_selected'.w,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }

    final days = active.map((k) => _engineCache[k]!.p50.length).reduce(min);
    if (days == 0) return const SizedBox.shrink();

    const maxRows = 12;
    final step = (days / maxRows).ceil().clamp(1, days);
    final sampleOffsets = <int>[
      for (int i = 0; i < days; i += step) i,
      if ((days - 1) % step != 0) days - 1,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 32,
        columnSpacing: 20,
        columns: [
          DataColumn(
              label: Text('day'.w,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textMuted))),
          for (final kind in active)
            DataColumn(
              label: Text(
                WesiLocale.isRussian ? kind.nameRu : kind.nameEn,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _engineColor[kind]),
              ),
            ),
        ],
        rows: sampleOffsets.map((i) {
          final date = DateTime.now().add(Duration(days: i + 1));
          final dateLabel = '${date.day.toString().padLeft(2, '0')}.'
              '${date.month.toString().padLeft(2, '0')}';
          return DataRow(cells: [
            DataCell(Text(dateLabel,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary))),
            for (final kind in active)
              DataCell(Text(
                CurrencyService.format(_engineCache[kind]!.p50[i]),
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textPrimary),
              )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _stats(ForecastPoint? last, double growth) {
    return Row(
      children: [
        _stat(
          'P50',
          last != null ? CurrencyService.format(last.p50) : '—',
          AppTheme.accentOrange,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P50 — медианный сценарий (50% вероятность)'
                : 'P50 — median scenario (50% probability)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
          growth: growth,
        ),
        const SizedBox(width: 8),
        _stat(
          'P10',
          last != null ? CurrencyService.format(last.p10) : '—',
          AppTheme.accentRed,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P10 — пессимистичный сценарий (10% хуже)'
                : 'P10 — worst-case (10th percentile)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        _stat(
          'P90',
          last != null ? CurrencyService.format(last.p90) : '—',
          AppTheme.accentGreen,
          Tooltip(
            message: WesiLocale.isRussian
                ? 'P90 — оптимистичный сценарий (90% лучше)'
                : 'P90 — best-case (90th percentile)',
            child: const Icon(Icons.info_outline,
                size: 14, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color, Widget tip,
      {double? growth}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 4),
                tip,
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            if (growth != null) ...[
              const SizedBox(height: 2),
              Text(
                '${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(1)}% ${'growth_over_period'.w}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: growth >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// «1 год / 2 года / 5 лет» — без склонения подпись выглядит калькой.
  static String _yearsWordRu(int years) {
    if (years == 1) return 'год';
    if (years >= 2 && years <= 4) return 'года';
    return 'лет';
  }

  Widget _periodChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // Короткие горизонты — днями, длинные — годами: «730 дн.» читается
        // хуже, чем «2 года», а планирование в долгосрок этим и меряют.
        ...const [7, 14, 30, 60, 90, 180].map((d) {
          final sel = _customRange == null && _forecastDays == d;
          return _periodChip(
            label: '$d ${'days'.w}',
            selected: sel,
            onTap: () => _changePeriod(d),
          );
        }),
        ...const [365, 730, 1095, 1825].map((d) {
          final years = d ~/ 365;
          final sel = _customRange == null && _forecastDays == d;
          return _periodChip(
            label: WesiLocale.isRussian
                ? '$years ${_yearsWordRu(years)}'
                : '$years ${years == 1 ? 'year' : 'years'}',
            selected: sel,
            onTap: () => _changePeriod(d),
          );
        }),
        // Ручной диапазон датами — вместо только фиксированных chips
        _periodChip(
          label: _customRange == null
              ? 'custom_range'.w
              : '${_fmtDate(_customRange!.start)} — ${_fmtDate(_customRange!.end)}',
          selected: _customRange != null,
          icon: Icons.calendar_month,
          onTap: _pickCustomRange,
        ),
      ],
    );
  }

  Widget _periodChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentOrange.withOpacity(0.2)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? AppTheme.accentOrange.withOpacity(0.5)
                  : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color:
                      selected ? AppTheme.accentOrange : AppTheme.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color:
                    selected ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Дата, соответствующая позиции X на графике.
  ///
  /// Ось X — это индекс дня в общем ряду «история + прогноз»: точки до
  /// [_historyWindowDays] отсчитываются назад от сегодня, дальше — вперёд.
  String _dateLabelForX(int x) {
    final now = DateTime.now();
    final offset = x - _historyWindowDays;
    final d = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final prefix = offset > 0
        ? (WesiLocale.isRussian ? 'Прогноз' : 'Forecast')
        : (WesiLocale.isRussian ? 'Факт' : 'Actual');
    return '$prefix · $dd.$mm.${d.year}';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickCustomRange() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: start,
      // Пять лет вперёд: столько же, сколько даёт самый длинный chip.
      lastDate: start.add(const Duration(days: 1825)),
      initialDateRange: _customRange ??
          DateTimeRange(
              start: start, end: start.add(Duration(days: _forecastDays))),
      locale: WesiLocale.isRussian ? const Locale('ru') : const Locale('en'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accentOrange,
            onPrimary: AppTheme.background,
            surface: AppTheme.surface,
            onSurface: AppTheme.textPrimary,
          ),
          scaffoldBackgroundColor: AppTheme.background,
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final days = picked.duration.inDays.clamp(1, 365);
    setState(() => _customRange = picked);
    if (days == _forecastDays) return;
    setState(() => _forecastDays = days);
    _loadData(full: false); // без полноэкранного лоадера
  }

  Widget _forecastChart() {
    if (_data.isEmpty) return const SizedBox(height: 300);

    final history = _data.where((d) => !d.isForecast).toList();

    // Ровно один активный движок — показываем деталировку (band/пунктир
    // P10-P90/тренд, управляется существующими тумблерами в _controls()),
    // используя цвет ЭТОГО движка. Ноль или несколько — режим сравнения:
    // только линия P50 на каждый активный движок, без полос (иначе на
    // графике станет нечитаемо), плюс легенда под графиком (см. build()).
    final singleEngine =
        _activeEngines.length == 1 ? _activeEngines.single : null;
    final singleResult =
        singleEngine != null ? _engineCache[singleEngine] : null;
    final singleColor =
        singleEngine != null ? _engineColor[singleEngine]! : AppTheme.accentOrange;

    final allY = <double>[
      for (final d in history) ...[d.p10, d.p50, d.p90],
      for (final kind in _activeEngines)
        if (_engineCache[kind] != null) ...[
          ..._engineCache[kind]!.p10,
          ..._engineCache[kind]!.p50,
          ..._engineCache[kind]!.p90,
        ],
    ];
    if (allY.isEmpty) allY.addAll([0, 1]); // все движки выключены — не падаем
    final rawMin = allY.reduce((a, b) => a < b ? a : b);
    final rawMax = allY.reduce((a, b) => a > b ? a : b);
    final pad = (rawMax - rawMin).abs() * 0.08 + 1;
    final minY = rawMin - pad;
    final maxY = rawMax + pad;

    List<FlSpot> spotsFor(List<double> series) => List.generate(
        series.length,
        (i) => FlSpot((_historyWindowDays + 1 + i).toDouble(), series[i]));

    return Container(
      height: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (_data.length / 6).clamp(1, 30).toDouble(),
                getTitlesWidget: (v, _) {
                  final i = v.toInt().clamp(0, _data.length - 1);
                  final day = DateTime.now().subtract(Duration(
                      days: _historyWindowDays -
                          _data[i].day.clamp(0, _historyWindowDays)));
                  // Для прогноза — дата вперёд
                  final d = _data[i].isForecast
                      ? DateTime.now()
                          .add(Duration(days: _data[i].day - _historyWindowDays))
                      : day;
                  return Text(
                    '${d.day}.${d.month}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 9),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          // Свой тултип: дефолтный у fl_chart светло-голубой (нечитаемо на
          // тёмной теме) и показывает только числа — по ним невозможно
          // понять, к какому дню относится значение.
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: AppTheme.surface.withOpacity(0.96),
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) {
                if (spots.isEmpty) return const [];
                final dateLabel = _dateLabelForX(spots.first.x.toInt());
                return List.generate(spots.length, (i) {
                  final spot = spots[i];
                  final value = CurrencyService.format(spot.y);
                  // Дату печатаем один раз — заголовком в первой строке,
                  // иначе она дублировалась бы на каждой серии.
                  final text = i == 0 ? '$dateLabel\n$value' : value;
                  return LineTooltipItem(
                    text,
                    TextStyle(
                      color: spot.bar.color ?? AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                });
              },
            ),
          ),
          minX: 0,
          maxX: (_data.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            if (singleResult != null) ...[
              // Заливка П10–П90: рисуем P90 с заливкой вниз, затем «стираем»
              // цветом фона всё ниже P10 — так полоса ограничена именно
              // диапазоном P10–P90, а не тянется до низа графика.
              if (_showConfidenceBands) ...[
                LineChartBarData(
                  spots: spotsFor(singleResult.p90),
                  isCurved: true,
                  color: Colors.transparent,
                  barWidth: 0,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: singleColor.withOpacity(0.08),
                  ),
                ),
                LineChartBarData(
                  spots: spotsFor(singleResult.p10),
                  isCurved: true,
                  color: Colors.transparent,
                  barWidth: 0,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: _chartBg),
                ),
              ],
              if (_showP10P90) ...[
                LineChartBarData(
                  spots: spotsFor(singleResult.p90),
                  isCurved: true,
                  color: singleColor.withOpacity(0.3),
                  barWidth: 1.2,
                  dashArray: const [4, 4],
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: spotsFor(singleResult.p10),
                  isCurved: true,
                  color: singleColor.withOpacity(0.3),
                  barWidth: 1.2,
                  dashArray: const [4, 4],
                  dotData: const FlDotData(show: false),
                ),
              ],
              if (_showTrendLine)
                LineChartBarData(
                  spots: spotsFor(singleResult.p50),
                  isCurved: true,
                  color: singleColor,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                ),
            ] else
              // Сравнение (0 или 2+ движков): только P50 на каждый активный,
              // без полос — иначе график становится нечитаемым.
              for (final kind in ForecastEngineKind.values)
                if (_activeEngines.contains(kind) && _engineCache[kind] != null)
                  LineChartBarData(
                    spots: spotsFor(_engineCache[kind]!.p50),
                    isCurved: true,
                    color: _engineColor[kind]!,
                    barWidth: 2.2,
                    dotData: const FlDotData(show: false),
                  ),
            LineChartBarData(
              spots: history
                  .map((d) => FlSpot(d.day.toDouble(), d.actual ?? d.p50))
                  .toList(),
              isCurved: true,
              color: Colors.white.withOpacity(0.75),
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      ),
    );
  }

  // ===== Режимы графика: прогноз / структура / тренд / сезонность =====

  Widget _chartModeTabs() {
    const modes = ['forecast', 'breakdown', 'trend', 'heatmap'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: modes.map((m) {
        final sel = _selectedChart == m;
        return GestureDetector(
          // Только смена содержимого графика, экран не перестраивается
          onTap: () => setState(() => _selectedChart = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.accentOrange.withOpacity(0.2)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: sel
                      ? AppTheme.accentOrange.withOpacity(0.5)
                      : AppTheme.glassBorder),
            ),
            child: Text(
              m.w,
              style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                color: sel ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _chartForMode() {
    switch (_selectedChart) {
      case 'breakdown':
        return _categoryChart();
      case 'trend':
        return _trendChart();
      case 'heatmap':
        return _seasonalityChart();
      default:
        return _forecastChart();
    }
  }

  Widget _chartFrame({required Widget child}) {
    return Container(
      height: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: child,
    );
  }

  /// Столбики по категориям: доход зелёный, расход красный.
  Widget _categoryChart() {
    if (_categoryBreakdown.isEmpty) {
      return _chartFrame(
        child: Center(
          child: Text('no_transactions'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final entries = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = entries.take(8).toList();
    final values = top.map((e) => e.value).toList();
    // Ось по фактическим данным: если все категории одного знака,
    // не растягиваем шкалу симметрично на пустую половину.
    final hi = values.reduce((a, b) => a > b ? a : b);
    final lo = values.reduce((a, b) => a < b ? a : b);
    final pad = (hi - lo).abs() * 0.15 + 1;

    return _chartFrame(
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (hi > 0 ? hi : 0) + pad,
          minY: (lo < 0 ? lo : 0) - pad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= top.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      top[i].key.length > 8
                          ? '${top[i].key.substring(0, 7)}…'
                          : top[i].key,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (int i = 0; i < top.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: top[i].value,
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color: top[i].value >= 0
                        ? AppTheme.accentGreen
                        : AppTheme.accentRed,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Дневная динамика нетто за историю — «куда двигались» деньги.
  Widget _trendChart() {
    final history = _data.where((d) => !d.isForecast).toList();
    if (history.length < 2) {
      return _chartFrame(
        child: Center(
          child: Text('no_transactions'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 1; i < history.length; i++) {
      final delta = (history[i].actual ?? history[i].p50) -
          (history[i - 1].actual ?? history[i - 1].p50);
      spots.add(FlSpot(history[i].day.toDouble(), delta));
    }

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15) + 1;

    return _chartFrame(
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.glassBorder.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (v, _) => Text(CurrencyService.format(v),
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (history.length / 6).clamp(1, 30).toDouble(),
                getTitlesWidget: (v, _) {
                  final d = DateTime.now().subtract(Duration(
                      days: _historyWindowDays -
                          v.toInt().clamp(0, _historyWindowDays)));
                  return Text('${d.day}.${d.month}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 9));
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY - pad,
          maxY: maxY + pad,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.accentOrange,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accentOrange.withOpacity(0.10),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      ),
    );
  }

  /// Сезонность по дню недели — прямой побочный продукт нового движка
  /// прогноза: показывает, какие дни недели обычно «тяжелее» или «легче».
  Widget _seasonalityChart() {
    if (!_forecast.seasonalityApplied || _forecast.weekdayFactor.isEmpty) {
      return _chartFrame(
        child: Center(
          child: Text('seasonality_off'.w,
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    final labels = WesiLocale.isRussian
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final values = _forecast.weekdayFactor;
    final maxAbs =
        values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b) + 1;

    return _chartFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('weekly_activity_heatmap'.w,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAbs,
                minY: -maxAbs,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.glassBorder.withOpacity(0.2),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, _) => Text(
                          CurrencyService.format(v),
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(labels[i],
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 10));
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (int i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i],
                          width: 22,
                          borderRadius: BorderRadius.circular(4),
                          color: values[i] >= 0
                              ? AppTheme.accentGreen
                              : AppTheme.accentRed,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _toggle('p10_p90_range'.w, _showP10P90,
            (v) => setState(() => _showP10P90 = v)),
        _toggle('confidence_bands'.w, _showConfidenceBands,
            (v) => setState(() => _showConfidenceBands = v)),
        _toggle('trend_line'.w, _showTrendLine,
            (v) => setState(() => _showTrendLine = v)),
        // DCF: приведение будущего баланса к сегодняшним деньгам имеет смысл
        // только для длинных горизонтов — показываем от года.
        if (_forecastDays >= 365)
          _toggle('discount_toggle'.w, _discountEnabled, (v) {
            setState(() => _discountEnabled = v);
            _loadData(full: false);
          }),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? AppTheme.accentOrange.withOpacity(0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value
                  ? AppTheme.accentOrange.withOpacity(0.4)
                  : AppTheme.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: value ? AppTheme.accentOrange : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _breakdown() {
    final sorted = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('category_breakdown'.w,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        ...sorted.take(5).map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppTheme.textSecondary))),
                  Text(CurrencyService.format(e.value.abs()),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: e.value >= 0
                              ? AppTheme.accentGreen
                              : AppTheme.accentRed)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _anomaliesSection() {
    if (_anomalies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WesiLocale.isRussian
              ? 'Аномалии (${_anomalies.length})'
              : 'Anomalies (${_anomalies.length})',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentRed),
        ),
        const SizedBox(height: 8),
        ..._anomalies.map((a) => Text(
              '• ${a.title}: ${CurrencyService.format(a.amount)}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            )),
      ],
    );
  }
}

class ForecastPoint {
  final int day;
  final double p10;
  final double p50;
  final double p90;
  final double? actual;
  final bool isForecast;

  ForecastPoint({
    required this.day,
    required this.p10,
    required this.p50,
    required this.p90,
    this.actual,
    required this.isForecast,
  });
}
