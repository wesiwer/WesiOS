import 'package:flutter/material.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';

class ChartRow {
  final String label;
  final double value;
  const ChartRow({required this.label, required this.value});
  ChartRow copyWith({String? label, double? value}) =>
      ChartRow(label: label ?? this.label, value: value ?? this.value);
}

/// Dialog to configure and insert a chart embed.
class ChartInsertDialog {
  static Future<Map<String, dynamic>?> show(BuildContext context, {required bool isRu}) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ChartInsertDialogBody(isRu: isRu),
    );
  }
}

class _ChartInsertDialogBody extends StatefulWidget {
  final bool isRu;
  const _ChartInsertDialogBody({required this.isRu});
  @override
  State<_ChartInsertDialogBody> createState() => _ChartInsertDialogBodyState();
}

class _ChartInsertDialogBodyState extends State<_ChartInsertDialogBody> {
  bool get _ru => widget.isRu;
  String chartType = 'bar';
  final titleCtrl = TextEditingController();
  String dataSource = 'manual';
  final rows = <ChartRow>[const ChartRow(label: '', value: 0)];

  @override
  void dispose() {
    titleCtrl.dispose();
    super.dispose();
  }

  Widget _chartTypeChip(String value, String label, IconData icon) {
    final isSelected = chartType == value;
    return GestureDetector(
      onTap: () => setState(() => chartType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withOpacity(0.18) : AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.accent.withOpacity(0.6) : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accent : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isSelected ? AppTheme.accent : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _dataSourceChip(String value, String label, IconData icon) {
    final isSelected = dataSource == value;
    return GestureDetector(
      onTap: () => setState(() => dataSource = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentGreen.withOpacity(0.18) : AppTheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.accentGreen.withOpacity(0.6) : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.accentGreen : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isSelected ? AppTheme.accentGreen : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text(_ru ? 'Подпись' : 'Label', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: Text(_ru ? 'Значение' : 'Value', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
            const SizedBox(width: 32),
          ],
        ),
        const SizedBox(height: 4),
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: TextEditingController(text: row.label),
                    onChanged: (v) => rows[i] = row.copyWith(label: v),
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _ru ? 'Янв' : 'Jan',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.glassBorder)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: TextEditingController(text: row.value.toString()),
                    onChanged: (v) => rows[i] = row.copyWith(value: double.tryParse(v) ?? 0),
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '100',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted.withOpacity(0.4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.glassBorder)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.remove_circle, size: 18, color: AppTheme.accentRed.withOpacity(0.7)),
                  onPressed: rows.length > 1 ? () => setState(() => rows.removeAt(i)) : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        HoverButton(
          onTap: () => setState(() => rows.add(const ChartRow(label: '', value: 0))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: AppTheme.surface.withOpacity(0.4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: AppTheme.accent),
              const SizedBox(width: 4),
              Text(_ru ? 'Добавить строку' : 'Add row', style: TextStyle(fontSize: 12, color: AppTheme.accent)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedDataPreview(String source) {
    String title;
    String description;
    switch (source) {
      case 'forecast':
        title = _ru ? 'Прогноз Wesi Forecast' : 'Wesi Forecast';
        description = _ru
            ? 'График будет построен на основе данных прогноза (Holt-Winters + Monte-Carlo). При открытии статьи данные подгрузятся актуальные.'
            : 'Chart based on forecast data (Holt-Winters + Monte-Carlo). Live data on article open.';
      case 'analytics':
        title = _ru ? 'Аналитика WesiOS' : 'WesiOS Analytics';
        description = _ru
            ? 'График будет построен на основе данных аналитики (транзакции, метрики, heatmap). Актуальные данные при каждом открытии.'
            : 'Chart based on analytics data (transactions, metrics, heatmap). Live data on every open.';
      case 'treasury':
        title = _ru ? 'Wesi Treasury' : 'Wesi Treasury';
        description = _ru
            ? 'График баланса на основе реальных транзакций. Данные обновляются при открытии статьи.'
            : 'Balance chart based on real transactions. Data updates on article open.';
      default:
        title = '';
        description = '';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 16, color: AppTheme.accentGreen),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentGreen)),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
        ],
      ),
    );
  }

  Map<String, dynamic>? _buildChartData() {
    if (dataSource == 'manual') {
      final validRows = rows.where((r) => r.label.isNotEmpty).toList();
      if (validRows.isEmpty) return null;
      return {
        'type': chartType,
        'title': titleCtrl.text.trim(),
        'source': 'manual',
        'data': validRows.map((r) => r.value).toList(),
        'labels': validRows.map((r) => r.label).toList(),
      };
    }
    return {
      'type': chartType,
      'title': titleCtrl.text.trim().isNotEmpty
          ? titleCtrl.text.trim()
          : (_ru ? 'Данные из $dataSource' : 'Data from $dataSource'),
      'source': dataSource,
      'data': <dynamic>[],
      'labels': <dynamic>[],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _ru ? 'График / Диаграмма' : 'Chart / Diagram',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_ru ? 'Тип графика' : 'Chart type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chartTypeChip('bar', _ru ? 'Столбчатый' : 'Bar', Icons.bar_chart),
                        _chartTypeChip('line', _ru ? 'Линейный' : 'Line', Icons.show_chart),
                        _chartTypeChip('pie', _ru ? 'Круговой' : 'Pie', Icons.pie_chart),
                        _chartTypeChip('area', _ru ? 'Областной' : 'Area', Icons.area_chart),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: _ru ? 'Заголовок' : 'Title',
                        labelStyle: TextStyle(color: AppTheme.textMuted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(_ru ? 'Источник данных' : 'Data source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _dataSourceChip('manual', _ru ? 'Вручную' : 'Manual', Icons.edit),
                        _dataSourceChip('forecast', _ru ? 'Прогноз' : 'Forecast', Icons.trending_up),
                        _dataSourceChip('analytics', _ru ? 'Аналитика' : 'Analytics', Icons.analytics),
                        _dataSourceChip('treasury', _ru ? 'Treasury' : 'Treasury', Icons.account_balance_wallet),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (dataSource == 'manual') _buildManualEditor() else _buildLinkedDataPreview(dataSource),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'), style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  HoverButton(
                    onTap: () {
                      final data = _buildChartData();
                      if (data != null) Navigator.pop(context, data);
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: AppTheme.accent,
                    child: Text(
                      _ru ? 'Вставить график' : 'Insert chart',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
