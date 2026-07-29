import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import 'services/sandbox_service.dart';
import 'services/forecast_engine.dart';
import 'services/what_if_store.dart';
import 'widgets/what_if_dialog.dart';

/// Прогноз внутри песочницы + конструктор собственных сценариев «Что если?».
///
/// Отличие от прогноза в Treasury: там сценарий один и живёт до закрытия
/// экрана. Здесь сценарии **именованные и сохраняются**, а на графике
/// одновременно рисуются базовый прогноз и все включённые сценарии — то есть
/// видно не «что будет», а «что будет при каждом из моих вариантов» рядом.
///
/// Данные берутся только из [SandboxService] — реальные транзакции Treasury
/// этот экран не читает и не пишет.
class SandboxForecastScreen extends StatefulWidget {
  const SandboxForecastScreen({super.key});

  @override
  State<SandboxForecastScreen> createState() => _SandboxForecastScreenState();
}

class _SandboxForecastScreenState extends State<SandboxForecastScreen> {
  final SandboxService _service = SandboxService();

  /// Палитра для линий сценариев. Базовый прогноз всегда оранжевый, сценарии
  /// разбираются по кругу — цветов достаточно, чтобы шесть штук на графике не
  /// сливались.
  static const List<Color> _palette = [
    Color(0xFF38BDF8),
    Color(0xFFA78BFA),
    Color(0xFF34D399),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFF60A5FA),
  ];

  ForecastResult _baseline = ForecastResult.empty();
  List<WhatIfPreset> _presets = [];
  final Map<String, ForecastResult> _results = {};
  final Set<String> _enabled = {};

  int _days = 30;
  double _startBalance = 0;
  bool _loading = true;

  String get _sym => CurrencyService.symbol;
  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final balance = await _service.getCurrentBalance();
    final baseline = await _service.generateForecast(days: _days);
    final presets = await WhatIfStore.getAll();

    _results.clear();
    for (final p in presets) {
      if (!_enabled.contains(p.id)) continue;
      _results[p.id] =
          await _service.generateForecast(days: _days, whatIf: p.scenario);
    }

    if (!mounted) return;
    setState(() {
      _startBalance = balance;
      _baseline = baseline;
      _presets = presets;
      _loading = false;
    });
  }

  /// Пересчитывает только один сценарий — при включении тумблера гонять весь
  /// экран через `_load` незачем, базовый прогноз от этого не меняется.
  Future<void> _toggle(WhatIfPreset preset) async {
    if (_enabled.contains(preset.id)) {
      setState(() {
        _enabled.remove(preset.id);
        _results.remove(preset.id);
      });
      return;
    }
    setState(() => _enabled.add(preset.id));
    final result =
        await _service.generateForecast(days: _days, whatIf: preset.scenario);
    if (!mounted) return;
    setState(() => _results[preset.id] = result);
  }

  Future<void> _setDays(int days) async {
    if (days == _days) return;
    setState(() => _days = days);
    await _load();
  }

  Future<void> _createPreset({WhatIfPreset? editing}) async {
    final scenario = await showDialog<WhatIfScenario>(
      context: context,
      builder: (_) => WhatIfDialog(
        initial: editing?.scenario ?? WhatIfScenario.none,
        forecastDays: _days,
        symbol: _sym,
      ),
    );
    if (scenario == null || !mounted) return;

    final name = await _askName(editing?.name ?? '');
    if (name == null || !mounted) return;

    final preset = editing == null
        ? WhatIfPreset(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            scenario: scenario,
            createdAt: DateTime.now(),
          )
        : editing.copyWith(name: name, scenario: scenario);

    await WhatIfStore.save(preset);
    _enabled.add(preset.id);
    await _load();
  }

  Future<String?> _askName(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(_ru ? 'Название сценария' : 'Scenario name',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          onSubmitted: (v) =>
              Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
          decoration: InputDecoration(
            hintText: _ru ? 'Например: Потеря клиента' : 'e.g. Lost a client',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(WesiLocale.get('cancel'),
                style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(context, v.isEmpty ? null : v);
            },
            child: Text(WesiLocale.get('save'),
                style: const TextStyle(color: AppTheme.accentOrange)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePreset(WhatIfPreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(_ru ? 'Удалить сценарий?' : 'Delete scenario?',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        content: Text(preset.name,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_ru ? 'Удалить' : 'Delete',
                style: const TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WhatIfStore.delete(preset.id);
    _enabled.remove(preset.id);
    _results.remove(preset.id);
    await _load();
  }

  Color _colorFor(String id) {
    final i = _presets.indexWhere((p) => p.id == id);
    return _palette[(i < 0 ? 0 : i) % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accentOrange,
        onPressed: () => _createPreset(),
        icon: const Icon(Icons.auto_graph, color: Colors.white),
        label: Text(_ru ? 'Свой сценарий' : 'New scenario',
            style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (kHasCustomTitleBar) const SizedBox(height: kTitleBarHeight),
            _header(),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentOrange.withOpacity(0.5)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                      children: [
                        _horizonChips(),
                        const SizedBox(height: 18),
                        if (_baseline.insufficientData)
                          _emptyState()
                        else ...[
                          _chart(),
                          const SizedBox(height: 18),
                          _verdicts(),
                          const SizedBox(height: 18),
                        ],
                        _presetList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, kHasCustomTitleBar ? 148 : 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ru ? 'Прогноз песочницы' : 'Sandbox forecast',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary),
                ),
                Text(
                  _ru
                      ? 'Свои сценарии «Что если?» на изолированных данных'
                      : 'Your own what-if scenarios on isolated data',
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _horizonChips() {
    const options = [7, 14, 30, 60, 90];
    return Wrap(
      spacing: 8,
      children: options.map((d) {
        final sel = d == _days;
        return GestureDetector(
          onTap: () => _setDays(d),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.accentOrange.withOpacity(0.16)
                  : AppTheme.surface.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel
                      ? AppTheme.accentOrange.withOpacity(0.5)
                      : AppTheme.glassBorder),
            ),
            child: Text(
              '$d ${_ru ? 'дн.' : 'd'}',
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

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.insights, size: 34, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            _ru
                ? 'Данных в песочнице пока мало'
                : 'Not enough sandbox data yet',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _ru
                ? 'Запустите готовый сценарий (Startup, Freelancer, Crisis) '
                    'или добавьте операции — прогноз строится минимум по неделе истории.'
                : 'Run a preset scenario or add transactions — the forecast '
                    'needs at least a week of history.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  /// График: базовая линия + по линии на каждый включённый сценарий.
  /// Все ряды начинаются из одной точки — текущего баланса песочницы, иначе
  /// расхождение сценариев читалось бы неправильно.
  Widget _chart() {
    final series = <_Series>[
      _Series(
        label: _ru ? 'Базовый' : 'Baseline',
        color: AppTheme.accentOrange,
        values: _baseline.p50,
        dashed: false,
      ),
      for (final p in _presets)
        if (_enabled.contains(p.id) && _results[p.id] != null)
          _Series(
            label: p.name,
            color: _colorFor(p.id),
            values: _results[p.id]!.p50,
            dashed: true,
          ),
    ].where((s) => s.values.isNotEmpty).toList();

    if (series.isEmpty) return _emptyState();

    final all = <double>[_startBalance, for (final s in series) ...s.values];
    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    if (lo > 0) lo = 0; // ноль всегда в кадре — по нему читается кассовый разрыв
    final pad = ((hi - lo).abs() * 0.12) + 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 18, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minY: lo - pad,
                maxY: hi + pad,
                minX: 0,
                maxX: _days.toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppTheme.glassBorder.withOpacity(0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) => Text(
                        _compact(value),
                        style: const TextStyle(
                            fontSize: 9, color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: (_days / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        final day = value.toInt();
                        if (day < 0 || day > _days) {
                          return const SizedBox.shrink();
                        }
                        final d = DateTime.now().add(Duration(days: day));
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${d.day.toString().padLeft(2, '0')}.'
                            '${d.month.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                fontSize: 9, color: AppTheme.textMuted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: AppTheme.accentRed.withOpacity(0.45),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: AppTheme.surface.withOpacity(0.96),
                    tooltipBorder:
                        BorderSide(color: AppTheme.accentOrange.withOpacity(0.4)),
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (spots) {
                      final day = spots.first.x.toInt();
                      final d = DateTime.now().add(Duration(days: day));
                      final dateLabel =
                          '${d.day.toString().padLeft(2, '0')}.'
                          '${d.month.toString().padLeft(2, '0')}.${d.year}';
                      return List.generate(spots.length, (i) {
                        final spot = spots[i];
                        final s = spot.barIndex < series.length
                            ? series[spot.barIndex]
                            : null;
                        final line =
                            '${s?.label ?? ''}: $_sym${spot.y.toStringAsFixed(0)}';
                        return LineTooltipItem(
                          i == 0 ? '$dateLabel\n$line' : line,
                          TextStyle(
                            color: s?.color ?? AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      });
                    },
                  ),
                ),
                lineBarsData: series
                    .map((s) => LineChartBarData(
                          spots: [
                            FlSpot(0, _startBalance),
                            ...List.generate(
                              s.values.length,
                              (i) => FlSpot((i + 1).toDouble(), s.values[i]),
                            ),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.22,
                          color: s.color,
                          barWidth: s.dashed ? 2 : 2.6,
                          dashArray: s.dashed ? [6, 4] : null,
                          dotData: const FlDotData(show: false),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: series
                .map((s) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 3, color: s.color),
                        const SizedBox(width: 6),
                        Text(s.label,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  /// Словесный разбор каждого включённого сценария: не только линия на
  /// графике, но и прямым текстом — куда придёт баланс, на сколько это
  /// отличается от базового и будет ли кассовый разрыв.
  Widget _verdicts() {
    final active = _presets
        .where((p) => _enabled.contains(p.id) && _results[p.id] != null)
        .toList();

    final baseEnd = _baseline.p50.isEmpty ? _startBalance : _baseline.p50.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ru ? 'Что получится' : 'What happens',
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        _verdictCard(
          label: _ru ? 'Базовый прогноз' : 'Baseline',
          color: AppTheme.accentOrange,
          end: baseEnd,
          delta: null,
          runway: _baseline.runwayDays,
          riskDay: _baseline.riskAlertDay,
        ),
        for (final p in active) ...[
          const SizedBox(height: 8),
          _verdictCard(
            label: p.name,
            color: _colorFor(p.id),
            end: _results[p.id]!.p50.isEmpty
                ? _startBalance
                : _results[p.id]!.p50.last,
            delta: (_results[p.id]!.p50.isEmpty
                    ? _startBalance
                    : _results[p.id]!.p50.last) -
                baseEnd,
            runway: _results[p.id]!.runwayDays,
            riskDay: _results[p.id]!.riskAlertDay,
          ),
        ],
        if (active.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _ru
                ? 'Включите сценарий ниже — он появится на графике рядом с базовым.'
                : 'Enable a scenario below — it will be drawn next to the baseline.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _verdictCard({
    required String label,
    required Color color,
    required double end,
    required double? delta,
    required int? runway,
    required int? riskDay,
  }) {
    final notes = <String>[];
    if (delta != null && delta.abs() >= 1) {
      final sign = delta > 0 ? '+' : '−';
      notes.add(
          '${_ru ? 'разница' : 'delta'} $sign$_sym${delta.abs().toStringAsFixed(0)}');
    }
    if (runway != null) {
      notes.add(_ru
          ? 'в минус на $runway-й день'
          : 'goes negative on day $runway');
    }
    if (riskDay != null && riskDay != runway) {
      notes.add(_ru
          ? 'риск разрыва с $riskDay-го дня'
          : 'cash-gap risk from day $riskDay');
    }
    if (notes.isEmpty) {
      notes.add(_ru ? 'кассовых разрывов нет' : 'no cash gaps');
    }

    final danger = runway != null || riskDay != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: danger ? AppTheme.accentRed.withOpacity(0.4) : color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 34, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  notes.join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: danger ? AppTheme.accentRed : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_sym${end.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: end < 0 ? AppTheme.accentRed : AppTheme.textPrimary,
                ),
              ),
              Text(
                _ru ? 'через $_days дн.' : 'in $_days days',
                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _ru ? 'Мои сценарии' : 'My scenarios',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            const Spacer(),
            if (_presets.isNotEmpty)
              Text('${_enabled.length}/${_presets.length}',
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        if (_presets.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              children: [
                Text(
                  _ru
                      ? 'Сценариев пока нет'
                      : 'No scenarios yet',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  _ru
                      ? '«Свой сценарий» внизу — задайте разовое событие '
                          'и/или сдвиг доходов и расходов в процентах. '
                          'График построится сам.'
                      : 'Tap “New scenario” below — add a one-off event and/or '
                          'shift income and expenses by a percentage. '
                          'The chart draws itself.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else
          ..._presets.map(_presetTile),
      ],
    );
  }

  Widget _presetTile(WhatIfPreset preset) {
    final on = _enabled.contains(preset.id);
    final color = _colorFor(preset.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(on ? 0.4 : 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: on ? color.withOpacity(0.45) : AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Switch(
            value: on,
            activeColor: color,
            onChanged: (_) => _toggle(preset),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  preset.summary(_sym, _ru),
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 17, color: AppTheme.textMuted),
            tooltip: _ru ? 'Изменить' : 'Edit',
            onPressed: () => _createPreset(editing: preset),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 17, color: AppTheme.textMuted),
            tooltip: _ru ? 'Удалить' : 'Delete',
            onPressed: () => _deletePreset(preset),
          ),
        ],
      ),
    );
  }

  String _compact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _Series {
  final String label;
  final Color color;
  final List<double> values;
  final bool dashed;

  const _Series({
    required this.label,
    required this.color,
    required this.values,
    required this.dashed,
  });
}

/// Кнопка входа в прогноз песочницы — чтобы не дублировать оформление
/// в самом экране песочницы.
class SandboxForecastButton extends StatelessWidget {
  const SandboxForecastButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return HoverButton(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SandboxForecastScreen()),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      backgroundColor: AppTheme.surface.withOpacity(0.3),
      child: Row(
        children: [
          const Icon(Icons.auto_graph, color: AppTheme.accentOrange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? 'Прогноз и «Что если?»' : 'Forecast & what-if',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                Text(
                  ru
                      ? 'Свои сценарии, графики строятся автоматически'
                      : 'Your own scenarios, charts drawn automatically',
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        ],
      ),
    );
  }
}
