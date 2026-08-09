from pathlib import Path

path = Path('lib/features/knowledge/widgets/article_body_view.dart')
text = path.read_text()

import_line = "import '../services/knowledge_linked_chart_service.dart';\n"
anchor = "import '../services/knowledge_service.dart';\n"
if import_line not in text:
    if anchor not in text:
        raise SystemExit('knowledge service import anchor not found')
    text = text.replace(anchor, anchor + import_line, 1)

start = text.find('class _InlineChart extends StatelessWidget {')
end = text.find('\nWidget _broken(', start)
if start < 0 or end < 0:
    if 'KnowledgeLinkedChartService().load(source)' in text:
        path.write_text(text)
        raise SystemExit(0)
    raise SystemExit('inline chart block not found')

replacement = r'''class _InlineChart extends StatelessWidget {
  final String data;
  const _InlineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> chartData;
    try {
      chartData = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return _broken(Icons.bar_chart, 'Chart');
    }

    final type = chartData['type'] as String? ?? 'bar';
    final title = chartData['title'] as String? ?? '';
    final source = chartData['source'] as String? ?? 'manual';

    if (source == 'manual') {
      final values = (chartData['data'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList();
      final labels = (chartData['labels'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      return _buildChart(type, title, source, values, labels);
    }

    return FutureBuilder<KnowledgeLinkedChartData>(
      future: KnowledgeLinkedChartService().load(source),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _linkedState(
            icon: Icons.sync_rounded,
            label: 'Loading live $source data…',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return _linkedState(
            icon: Icons.error_outline_rounded,
            label: 'Live $source data unavailable',
          );
        }
        final linked = snapshot.data ?? KnowledgeLinkedChartData.empty;
        if (linked.values.isEmpty) {
          return _linkedState(
            icon: Icons.insights_outlined,
            label: 'No real $source data yet',
          );
        }
        return _buildChart(
          type,
          title,
          source,
          linked.values,
          linked.labels,
        );
      },
    );
  }

  Widget _buildChart(
    String type,
    String title,
    String source,
    List<double> values,
    List<String> labels,
  ) {
    if (values.isEmpty) return _broken(Icons.bar_chart, 'Chart');

    final safeLabels = List<String>.generate(
      values.length,
      (index) => index < labels.length ? labels[index] : '${index + 1}',
    );
    final barGroups = values.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value,
            color: AppTheme.accent,
            width: values.length > 8 ? 10 : 16,
          ),
        ],
      );
    }).toList();

    Widget bottomTitle(double value, TitleMeta meta) {
      final index = value.toInt();
      if (index < 0 || index >= safeLabels.length) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
        axisSide: meta.axisSide,
        child: Text(
          safeLabels[index],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9, color: AppTheme.textMuted),
        ),
      );
    }

    final commonTitles = FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: bottomTitle,
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget: (value, _) => Text(
            value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
            style: TextStyle(fontSize: 9, color: AppTheme.textMuted),
          ),
        ),
      ),
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
    );

    Widget chartWidget;
    switch (type) {
      case 'line':
      case 'area':
        chartWidget = LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.glassBorder),
            ),
            titlesData: commonTitles,
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: values.asMap().entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                    .toList(),
                color: AppTheme.accent,
                barWidth: 2,
                belowBarData: BarAreaData(
                  show: type == 'area',
                  color: AppTheme.accent.withOpacity(.18),
                ),
                dotData: FlDotData(show: values.length <= 10),
              ),
            ],
          ),
        );
        break;
      case 'pie':
        final positive = values.map((v) => v.abs()).toList();
        final total = positive.fold<double>(0, (sum, value) => sum + value);
        if (total <= 0) return _linkedState(icon: Icons.pie_chart_outline, label: 'No positive values to chart');
        chartWidget = PieChart(
          PieChartData(
            sections: positive.asMap().entries.map((entry) {
              final fraction = entry.value / total;
              final palette = [
                AppTheme.accent,
                AppTheme.accentGreen,
                AppTheme.lightAccentBlue,
                AppTheme.accentRed,
                AppTheme.primary,
              ];
              return PieChartSectionData(
                value: entry.value,
                title: '${(fraction * 100).toStringAsFixed(0)}%',
                color: palette[entry.key % palette.length],
                radius: 58,
                titleStyle: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
        );
        break;
      case 'bar':
      default:
        chartWidget = BarChart(
          BarChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.glassBorder),
            ),
            titlesData: commonTitles,
            borderData: FlBorderData(show: false),
            barGroups: barGroups,
          ),
        );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          if (source != 'manual')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.link, size: 12, color: AppTheme.accentGreen),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Live: $source',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: AppTheme.accentGreen),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 200, child: chartWidget),
        ],
      ),
    );
  }

  Widget _linkedState({
    required IconData icon,
    required String label,
    bool loading = false,
  }) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: AppTheme.textMuted),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
'''

text = text[:start] + replacement + text[end:]

for stale in (
    "[120.0, 135.0, 128.0, 155.0, 170.0, 185.0, 195.0, 210.0]",
    "[45.0, 62.0, 38.0, 75.0, 55.0, 88.0]",
    "[5000.0, 4200.0, 6800.0, 5500.0, 7200.0, 8100.0, 7800.0]",
):
    if stale in text:
        raise SystemExit(f'stale demo series survived: {stale}')

path.write_text(text)
