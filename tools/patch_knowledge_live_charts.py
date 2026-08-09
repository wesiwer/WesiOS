from pathlib import Path

path = Path('lib/features/knowledge/widgets/article_body_view.dart')
text = path.read_text(encoding='utf-8')

import_anchor = "import '../services/knowledge_service.dart';\n"
linked_import = "import '../services/knowledge_linked_chart_service.dart';\n"
if linked_import not in text:
    if import_anchor not in text:
        raise SystemExit('Knowledge import anchor not found')
    text = text.replace(import_anchor, import_anchor + linked_import, 1)

start_marker = 'class _InlineChart extends StatelessWidget {'
end_marker = '\nWidget _broken(IconData icon, String label) => Container('
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('Inline chart replacement markers not found')

replacement = r'''class _InlineChart extends StatefulWidget {
  final String data;
  const _InlineChart({required this.data});

  @override
  State<_InlineChart> createState() => _InlineChartState();
}

class _InlineChartState extends State<_InlineChart> {
  final KnowledgeLinkedChartService _linked = KnowledgeLinkedChartService();
  String? _loadedSource;
  Future<KnowledgeLinkedChartData>? _linkedFuture;

  @override
  void didUpdateWidget(covariant _InlineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _loadedSource = null;
      _linkedFuture = null;
    }
  }

  Future<KnowledgeLinkedChartData> _futureFor(String source) {
    if (_loadedSource != source || _linkedFuture == null) {
      _loadedSource = source;
      _linkedFuture = _linked.load(source);
    }
    return _linkedFuture!;
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> chartData;
    try {
      chartData = jsonDecode(widget.data);
    } catch (_) {
      return _broken(Icons.bar_chart, 'Chart');
    }

    final source = chartData['source'] as String? ?? 'manual';
    if (source == 'manual') {
      try {
        final values = (chartData['data'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList();
        final labels = (chartData['labels'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return _renderChart(chartData, values, labels);
      } catch (_) {
        return _broken(Icons.bar_chart, 'Chart');
      }
    }

    return FutureBuilder<KnowledgeLinkedChartData>(
      future: _futureFor(source),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _chartState(
            icon: Icons.sync_rounded,
            label: 'Loading live $source data…',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return _chartState(
            icon: Icons.error_outline_rounded,
            label: 'Live $source data unavailable',
          );
        }
        final linked = snapshot.data ?? KnowledgeLinkedChartData.empty;
        if (linked.values.isEmpty) {
          return _chartState(
            icon: Icons.query_stats_rounded,
            label: 'No real $source data yet',
          );
        }
        return _renderChart(chartData, linked.values, linked.labels);
      },
    );
  }

  Widget _chartState({
    required IconData icon,
    required String label,
    bool loading = false,
  }) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
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

  Widget _renderChart(
    Map<String, dynamic> chartData,
    List<double> values,
    List<String> labels,
  ) {
    if (values.isEmpty) return _broken(Icons.bar_chart, 'Chart');

    final type = chartData['type'] as String? ?? 'bar';
    final title = chartData['title'] as String? ?? '';
    final source = chartData['source'] as String? ?? 'manual';

    final barGroups = values.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(toY: e.value, color: AppTheme.accent, width: 16),
        ],
      );
    }).toList();

    Widget bottomTitle(double value, TitleMeta _) {
      final index = value.toInt();
      if (index < 0 || index >= labels.length) return const SizedBox.shrink();
      return Text(
        labels[index],
        style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
      );
    }

    Widget leftTitle(double value, TitleMeta _) => Text(
          value.toInt().toString(),
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        );

    final titles = FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottomTitle),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: leftTitle,
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            titlesData: titles,
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: values.asMap().entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                    .toList(),
                color: AppTheme.accent,
                barWidth: 2,
                dotData: FlDotData(show: type == 'line'),
                belowBarData: BarAreaData(
                  show: type == 'area',
                  color: AppTheme.accent.withOpacity(0.2),
                ),
              ),
            ],
          ),
        );
        break;
      case 'pie':
        final positive = values.map((v) => v < 0 ? v.abs() : v).toList();
        final total = positive.fold<double>(0, (sum, value) => sum + value);
        chartWidget = PieChart(
          PieChartData(
            sections: positive.asMap().entries.map((e) {
              final pct = total > 0 ? e.value / total : 0;
              return PieChartSectionData(
                value: e.value,
                title: '${(pct * 100).toStringAsFixed(0)}%',
                color: [
                  AppTheme.accent,
                  AppTheme.accentGreen,
                  AppTheme.accentOrange,
                  AppTheme.accentRed,
                  AppTheme.lightAccentBlue,
                ][e.key % 5],
                radius: 60,
                titleStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
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
            titlesData: titles,
            borderData: FlBorderData(show: false),
            barGroups: barGroups,
          ),
        );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.3),
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
                  Text(
                    'Live: $source',
                    style: TextStyle(fontSize: 10, color: AppTheme.accentGreen),
                  ),
                ],
              ),
            ),
          SizedBox(height: 200, child: chartWidget),
        ],
      ),
    );
  }
}
'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8')
print('Knowledge linked chart UI switched from demo arrays to live service.')
