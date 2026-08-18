from pathlib import Path
import re


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    out, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"regex patch failed ({count}): {label}")
    return out


path = Path('lib/features/ai/widgets/wesi_ai_visualization.dart')
text = path.read_text(encoding='utf-8')

responsive_table = r'''class WesiAiTableBlock extends StatelessWidget {
  static const double _compactBreakpoint = 560;

  final WesiAiTableData table;

  const WesiAiTableBlock({super.key, required this.table});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: table.toTsv()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Таблица скопирована')),
    );
  }

  Widget _buildCompactTable(ThemeData theme) {
    if (table.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Нет данных',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) ...[
          if (rowIndex > 0) Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var columnIndex = 0;
                    columnIndex < table.headers.length;
                    columnIndex++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: columnIndex == table.headers.length - 1 ? 0 : 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          flex: 2,
                          child: Text(
                            table.headers[columnIndex],
                            softWrap: true,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          flex: 3,
                          child: SelectableText(
                            columnIndex < table.rows[rowIndex].length
                                ? table.rows[rowIndex][columnIndex]
                                : '',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWideTable() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final header in table.headers)
              DataColumn(
                label: Text(
                  header,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
          rows: [
            for (final row in table.rows)
              DataRow(
                cells: [
                  for (var i = 0; i < table.headers.length; i++)
                    DataCell(SelectableText(i < row.length ? row[i] : '')),
                ],
              ),
          ],
          headingRowHeight: 44,
          dataRowMinHeight: 42,
          dataRowMaxHeight: 72,
          horizontalMargin: 14,
          columnSpacing: 24,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 14,
                  7,
                  6,
                  6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        compact ? 'Таблица · ${table.rows.length}' : 'Таблица',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Копировать таблицу',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_all_outlined, size: 19),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              if (compact) _buildCompactTable(theme) else _buildWideTable(),
            ],
          ),
        );
      },
    );
  }
}

enum WesiAiChartType'''

text = regex_once(
    text,
    r'class WesiAiTableBlock extends StatelessWidget \{.*?\n\}\n\nenum WesiAiChartType',
    responsive_table,
    'responsive table block',
)

responsive_chart = r'''class WesiAiChartBlock extends StatelessWidget {
  static const double _compactBreakpoint = 560;

  final WesiAiChartSpec spec;
  const WesiAiChartBlock({super.key, required this.spec});

  String _percent(double value) {
    if (value >= 10) return '${value.toStringAsFixed(0)}%';
    return '${value.toStringAsFixed(1)}%';
  }

  Widget _compactPieLegend(ThemeData theme, List<Color> accents) {
    final values = spec.series.first.values
        .map((value) => math.max(0.0, value))
        .toList(growable: false);
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (var index = 0; index < spec.labels.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: accents[index % accents.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      spec.labels[index],
                      softWrap: true,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _percent(values[index] / total * 100),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accents = <Color>[
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      theme.colorScheme.error,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;
        final chartHeight = compact
            ? (spec.type == WesiAiChartType.pie ? 178.0 : 200.0)
            : 230.0;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 10 : 12,
            compact ? 10 : 14,
            compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spec.title.isNotEmpty)
                Text(
                  spec.title,
                  softWrap: true,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (spec.description.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  spec.description,
                  softWrap: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: compact ? 8 : 12),
              SizedBox(
                height: chartHeight,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WesiAiChartPainter(
                    spec: spec,
                    foreground: theme.colorScheme.onSurface,
                    muted: theme.colorScheme.outlineVariant,
                    accents: accents,
                    compact: compact,
                  ),
                ),
              ),
              if (compact && spec.type == WesiAiChartType.pie)
                _compactPieLegend(theme, accents),
              if (spec.type != WesiAiChartType.pie &&
                  spec.type != WesiAiChartType.scatter &&
                  spec.series.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: compact ? 9 : 12,
                  runSpacing: 5,
                  children: [
                    for (var index = 0;
                        index < spec.series.length;
                        index++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: accents[index % accents.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            spec.series[index].name,
                            style: compact ? theme.textTheme.bodySmall : null,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WesiAiChartPainter extends CustomPainter {
  final WesiAiChartSpec spec;
  final Color foreground;
  final Color muted;
  final List<Color> accents;
  final bool compact;

  const _WesiAiChartPainter({
    required this.spec,
    required this.foreground,
    required this.muted,
    required this.accents,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (spec.type) {
      case WesiAiChartType.bar:
        _paintBar(canvas, size);
        break;
      case WesiAiChartType.line:
        _paintLine(canvas, size);
        break;
      case WesiAiChartType.pie:
        _paintPie(canvas, size);
        break;
      case WesiAiChartType.scatter:
        _paintScatter(canvas, size);
        break;
    }
  }

  Rect _plot(Size size) {
    final left = compact ? 31.0 : 36.0;
    final right = compact ? 6.0 : 8.0;
    final bottom = compact ? 31.0 : 40.0;
    return Rect.fromLTWH(
      left,
      8,
      math.max(20.0, size.width - left - right),
      math.max(20.0, size.height - bottom),
    );
  }

  List<double> get _allValues =>
      <double>[for (final series in spec.series) ...series.values];

  (double, double) _range(List<double> values) {
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if (minValue == maxValue) {
      final pad = minValue == 0 ? 1.0 : minValue.abs() * 0.1;
      minValue -= pad;
      maxValue += pad;
    }
    if (minValue > 0) minValue = 0;
    return (minValue, maxValue);
  }

  double _y(double value, Rect plot, double minValue, double maxValue) =>
      plot.bottom - ((value - minValue) / (maxValue - minValue)) * plot.height;

  void _axes(Canvas canvas, Rect plot, double minValue, double maxValue) {
    final grid = Paint()
      ..color = muted.withOpacity(0.55)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = maxValue - (maxValue - minValue) * index / 4;
      _text(
        canvas,
        _format(value),
        Offset(0, y - 7),
        compact ? 9 : 10,
        foreground.withOpacity(0.72),
        maxWidth: compact ? 29 : 34,
      );
    }
  }

  int _labelStride(int count, double width) {
    if (count <= 1) return 1;
    final target = math.max(2, (width / (compact ? 58 : 48)).floor());
    if (count <= target) return 1;
    return (count / target).ceil();
  }

  bool _showLabel(int index, int count, int stride) =>
      index % stride == 0 || index == count - 1;

  double _labelLeft(Rect plot, double center, double maxWidth) =>
      (center - maxWidth / 2)
          .clamp(plot.left, math.max(plot.left, plot.right - maxWidth))
          .toDouble();

  void _paintBar(Canvas canvas, Size size) {
    final plot = _plot(size);
    final (minValue, maxValue) = _range(_allValues);
    _axes(canvas, plot, minValue, maxValue);
    final groupWidth = plot.width / spec.labels.length;
    final barWidth = math.max(2.0, groupWidth * 0.72 / spec.series.length);
    final zeroY = _y(0, plot, minValue, maxValue);
    final stride = _labelStride(spec.labels.length, plot.width);

    for (var index = 0; index < spec.labels.length; index++) {
      for (var seriesIndex = 0;
          seriesIndex < spec.series.length;
          seriesIndex++) {
        final value = spec.series[seriesIndex].values[index];
        final valueY = _y(value, plot, minValue, maxValue);
        final left = plot.left +
            index * groupWidth +
            groupWidth * 0.14 +
            seriesIndex * barWidth;
        final rect = Rect.fromLTRB(
          left,
          math.min(zeroY, valueY),
          left + barWidth * 0.82,
          math.max(zeroY, valueY),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = accents[seriesIndex % accents.length],
        );
      }

      if (_showLabel(index, spec.labels.length, stride)) {
        final maxWidth = math.min(
          compact ? 58.0 : 80.0,
          math.max(groupWidth * stride, compact ? 36.0 : groupWidth),
        );
        final center = plot.left + index * groupWidth + groupWidth / 2;
        _text(
          canvas,
          spec.labels[index],
          Offset(_labelLeft(plot, center, maxWidth), plot.bottom + 6),
          compact ? 8.5 : 9,
          foreground.withOpacity(0.72),
          maxWidth: maxWidth,
        );
      }
    }
  }

  void _paintLine(Canvas canvas, Size size) {
    final plot = _plot(size);
    final (minValue, maxValue) = _range(_allValues);
    _axes(canvas, plot, minValue, maxValue);
    for (var seriesIndex = 0;
        seriesIndex < spec.series.length;
        seriesIndex++) {
      final values = spec.series[seriesIndex].values;
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final x = values.length == 1
            ? plot.center.dx
            : plot.left + plot.width * index / (values.length - 1);
        final point = Offset(x, _y(values[index], plot, minValue, maxValue));
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(
          point,
          compact ? 2.8 : 3.2,
          Paint()..color = accents[seriesIndex % accents.length],
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accents[seriesIndex % accents.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 2 : 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final stride = _labelStride(spec.labels.length, plot.width);
    for (var index = 0; index < spec.labels.length; index++) {
      if (!_showLabel(index, spec.labels.length, stride)) continue;
      final x = spec.labels.length == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (spec.labels.length - 1);
      final maxWidth = compact ? 58.0 : 72.0;
      _text(
        canvas,
        spec.labels[index],
        Offset(_labelLeft(plot, x, maxWidth), plot.bottom + 6),
        compact ? 8.5 : 9,
        foreground.withOpacity(0.72),
        maxWidth: maxWidth,
      );
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final values = spec.series.first.values
        .map((value) => math.max(0.0, value))
        .toList(growable: false);
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final radius = compact
        ? math.min(size.width * 0.31, size.height * 0.42)
        : math.min(size.width * 0.28, size.height * 0.38);
    final center = compact
        ? Offset(size.width / 2, size.height / 2)
        : Offset(size.width * 0.34, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = accents[index % accents.length],
      );
      start += sweep;
    }

    if (compact) return;

    var y = 18.0;
    for (var index = 0; index < spec.labels.length && index < 8; index++) {
      canvas.drawCircle(
        Offset(size.width * 0.68, y + 5),
        4,
        Paint()..color = accents[index % accents.length],
      );
      _text(
        canvas,
        '${spec.labels[index]} · ${_format(values[index] / total * 100)}%',
        Offset(size.width * 0.68 + 10, y - 2),
        10,
        foreground,
        maxWidth: size.width * 0.3,
      );
      y += 24;
    }
  }

  void _paintScatter(Canvas canvas, Size size) {
    final plot = _plot(size);
    final xs = spec.points.map((point) => point.x).toList(growable: false);
    final ys = spec.points.map((point) => point.y).toList(growable: false);
    var minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    var minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    if (minX == maxX) {
      minX -= 1;
      maxX += 1;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    _axes(canvas, plot, minY, maxY);
    for (final point in spec.points) {
      final x = plot.left + (point.x - minX) / (maxX - minX) * plot.width;
      final y = _y(point.y, plot, minY, maxY);
      canvas.drawCircle(
        Offset(x, y),
        compact ? 4 : 4.5,
        Paint()..color = accents.first,
      );
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    double size,
    Color color, {
    double maxWidth = 80,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  String _format(double value) {
    final abs = value.abs();
    if (abs >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    if ((value - value.roundToDouble()).abs() < 0.001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _WesiAiChartPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.foreground != foreground ||
      oldDelegate.muted != muted ||
      oldDelegate.compact != compact;
}
'''

text = regex_once(
    text,
    r'class WesiAiChartBlock extends StatelessWidget \{.*\Z',
    responsive_chart,
    'responsive chart block and painter',
)

path.write_text(text, encoding='utf-8')
