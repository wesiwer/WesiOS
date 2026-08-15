import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WesiAiTableData {
  final List<String> headers;
  final List<List<String>> rows;

  const WesiAiTableData({required this.headers, required this.rows});

  static WesiAiTableData? tryParseMarkdown(List<String> lines) {
    if (lines.length < 2) return null;
    final header = _cells(lines.first);
    final separator = _cells(lines[1]);
    if (header.length < 2 || separator.length != header.length) return null;
    final separatorPattern = RegExp(r'^:?-{3,}:?$');
    if (!separator.every((cell) => separatorPattern.hasMatch(cell.trim())))
      return null;
    final rows = <List<String>>[];
    for (final line in lines.skip(2)) {
      if (!line.contains('|')) break;
      final cells = _cells(line);
      if (cells.isEmpty) break;
      rows.add(List<String>.generate(
        header.length,
        (index) => index < cells.length ? cells[index] : '',
      ));
      if (rows.length >= 50) break;
    }
    return WesiAiTableData(headers: header, rows: rows);
  }

  static List<String> _cells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    final cells = <String>[];
    final buffer = StringBuffer();
    var escaped = false;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '|') {
        cells.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  String toTsv() => <String>[
        headers.join('\t'),
        ...rows.map((row) => row.join('\t')),
      ].join('\n');
}

class WesiAiTableBlock extends StatelessWidget {
  final WesiAiTableData table;

  const WesiAiTableBlock({super.key, required this.table});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: table.toTsv()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Таблица скопирована')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.fromLTRB(14, 7, 6, 6),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Таблица',
                        style: TextStyle(fontWeight: FontWeight.w700))),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final header in table.headers)
                  DataColumn(
                      label: Text(header,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
              rows: [
                for (final row in table.rows)
                  DataRow(cells: [
                    for (var i = 0; i < table.headers.length; i++)
                      DataCell(SelectableText(i < row.length ? row[i] : '')),
                  ]),
              ],
              headingRowHeight: 44,
              dataRowMinHeight: 42,
              dataRowMaxHeight: 72,
              horizontalMargin: 14,
              columnSpacing: 24,
            ),
          ),
        ],
      ),
    );
  }
}

enum WesiAiChartType { bar, line, pie, scatter }

class WesiAiChartSeries {
  final String name;
  final List<double> values;
  const WesiAiChartSeries({required this.name, required this.values});
}

class WesiAiScatterPoint {
  final double x;
  final double y;
  final String label;
  const WesiAiScatterPoint({required this.x, required this.y, this.label = ''});
}

class WesiAiChartSpec {
  final WesiAiChartType type;
  final String title;
  final String description;
  final List<String> labels;
  final List<WesiAiChartSeries> series;
  final List<WesiAiScatterPoint> points;

  const WesiAiChartSpec({
    required this.type,
    required this.title,
    required this.description,
    required this.labels,
    required this.series,
    required this.points,
  });

  static WesiAiChartSpec? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final type = switch ('${decoded['type'] ?? ''}'.toLowerCase()) {
        'bar' => WesiAiChartType.bar,
        'line' => WesiAiChartType.line,
        'pie' => WesiAiChartType.pie,
        'scatter' => WesiAiChartType.scatter,
        _ => null,
      };
      if (type == null) return null;
      final title = '${decoded['title'] ?? ''}'.trim();
      final description = '${decoded['description'] ?? ''}'.trim();
      if (title.length > 160 || description.length > 500) return null;
      final labels = <String>[];
      final rawLabels = decoded['labels'];
      if (rawLabels is List) {
        for (final item in rawLabels.take(24)) {
          final label = '$item'.trim();
          if (label.length > 80) return null;
          labels.add(label);
        }
      }
      final series = <WesiAiChartSeries>[];
      final rawSeries = decoded['series'];
      if (rawSeries is List) {
        for (final item in rawSeries.take(4)) {
          if (item is! Map) return null;
          final name = '${item['name'] ?? ''}'.trim();
          if (name.length > 80) return null;
          final rawValues = item['values'];
          if (rawValues is! List) return null;
          final values = <double>[];
          for (final value in rawValues.take(24)) {
            final number =
                value is num ? value.toDouble() : double.tryParse('$value');
            if (number == null || !number.isFinite || number.abs() > 1e15)
              return null;
            values.add(number);
          }
          if (values.isEmpty) return null;
          series.add(WesiAiChartSeries(name: name, values: values));
        }
      }
      final points = <WesiAiScatterPoint>[];
      final rawPoints = decoded['points'];
      if (rawPoints is List) {
        for (final item in rawPoints.take(50)) {
          if (item is! Map) return null;
          final x = item['x'];
          final y = item['y'];
          final dx = x is num ? x.toDouble() : double.tryParse('$x');
          final dy = y is num ? y.toDouble() : double.tryParse('$y');
          if (dx == null || dy == null || !dx.isFinite || !dy.isFinite)
            return null;
          final label = '${item['label'] ?? ''}'.trim();
          if (label.length > 80) return null;
          points.add(WesiAiScatterPoint(x: dx, y: dy, label: label));
        }
      }
      if (type == WesiAiChartType.scatter) {
        if (points.length < 2) return null;
      } else {
        if (labels.isEmpty || series.isEmpty) return null;
        if (series.any((item) => item.values.length != labels.length))
          return null;
        if (type == WesiAiChartType.pie && series.length != 1) return null;
      }
      return WesiAiChartSpec(
        type: type,
        title: title,
        description: description,
        labels: labels,
        series: series,
        points: points,
      );
    } catch (_) {
      return null;
    }
  }
}

class WesiAiChartBlock extends StatelessWidget {
  final WesiAiChartSpec spec;
  const WesiAiChartBlock({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accents = <Color>[
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      theme.colorScheme.error,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.title.isNotEmpty)
            Text(spec.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          if (spec.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(spec.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            width: double.infinity,
            child: CustomPaint(
              painter: _WesiAiChartPainter(
                spec: spec,
                foreground: theme.colorScheme.onSurface,
                muted: theme.colorScheme.outlineVariant,
                accents: accents,
              ),
            ),
          ),
          if (spec.type != WesiAiChartType.scatter &&
              spec.series.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (var index = 0; index < spec.series.length; index++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: accents[index % accents.length],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(spec.series[index].name),
                  ]),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WesiAiChartPainter extends CustomPainter {
  final WesiAiChartSpec spec;
  final Color foreground;
  final Color muted;
  final List<Color> accents;

  const _WesiAiChartPainter(
      {required this.spec,
      required this.foreground,
      required this.muted,
      required this.accents});

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

  Rect _plot(Size size) => Rect.fromLTWH(
      36, 8, math.max(20.0, size.width - 44), math.max(20.0, size.height - 40));
  List<double> get _allValues =>
      <double>[for (final s in spec.series) ...s.values];

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
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = maxValue - (maxValue - minValue) * i / 4;
      _text(canvas, _format(value), Offset(0, y - 7), 10,
          foreground.withOpacity(0.72),
          maxWidth: 34);
    }
  }

  void _paintBar(Canvas canvas, Size size) {
    final plot = _plot(size);
    final (minValue, maxValue) = _range(_allValues);
    _axes(canvas, plot, minValue, maxValue);
    final groupWidth = plot.width / spec.labels.length;
    final barWidth = math.max(2.0, groupWidth * 0.72 / spec.series.length);
    final zeroY = _y(0, plot, minValue, maxValue);
    for (var i = 0; i < spec.labels.length; i++) {
      for (var s = 0; s < spec.series.length; s++) {
        final value = spec.series[s].values[i];
        final valueY = _y(value, plot, minValue, maxValue);
        final left =
            plot.left + i * groupWidth + groupWidth * 0.14 + s * barWidth;
        final rect = Rect.fromLTRB(left, math.min(zeroY, valueY),
            left + barWidth * 0.82, math.max(zeroY, valueY));
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = accents[s % accents.length]);
      }
      if (spec.labels.length <= 10 || i.isEven) {
        _text(
            canvas,
            spec.labels[i],
            Offset(plot.left + i * groupWidth, plot.bottom + 6),
            9,
            foreground.withOpacity(0.72),
            maxWidth: groupWidth);
      }
    }
  }

  void _paintLine(Canvas canvas, Size size) {
    final plot = _plot(size);
    final (minValue, maxValue) = _range(_allValues);
    _axes(canvas, plot, minValue, maxValue);
    for (var s = 0; s < spec.series.length; s++) {
      final values = spec.series[s].values;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? plot.center.dx
            : plot.left + plot.width * i / (values.length - 1);
        final point = Offset(x, _y(values[i], plot, minValue, maxValue));
        if (i == 0)
          path.moveTo(point.dx, point.dy);
        else
          path.lineTo(point.dx, point.dy);
        canvas.drawCircle(
            point, 3.2, Paint()..color = accents[s % accents.length]);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = accents[s % accents.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
    for (var i = 0; i < spec.labels.length; i++) {
      if (spec.labels.length > 8 && !i.isEven) continue;
      final x = spec.labels.length == 1
          ? plot.center.dx
          : plot.left + plot.width * i / (spec.labels.length - 1);
      _text(canvas, spec.labels[i], Offset(x - 24, plot.bottom + 6), 9,
          foreground.withOpacity(0.72),
          maxWidth: 48);
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final values = spec.series.first.values
        .map((v) => math.max(0.0, v))
        .toList(growable: false);
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final radius = math.min(size.width * 0.28, size.height * 0.38);
    final rect = Rect.fromCircle(
        center: Offset(size.width * 0.34, size.height / 2), radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(rect, start, sweep, true,
          Paint()..color = accents[i % accents.length]);
      start += sweep;
    }
    var y = 18.0;
    for (var i = 0; i < spec.labels.length && i < 8; i++) {
      canvas.drawCircle(Offset(size.width * 0.68, y + 5), 4,
          Paint()..color = accents[i % accents.length]);
      _text(canvas, '${spec.labels[i]} · ${_format(values[i] / total * 100)}%',
          Offset(size.width * 0.68 + 10, y - 2), 10, foreground,
          maxWidth: size.width * 0.3);
      y += 24;
    }
  }

  void _paintScatter(Canvas canvas, Size size) {
    final plot = _plot(size);
    final xs = spec.points.map((p) => p.x).toList(growable: false);
    final ys = spec.points.map((p) => p.y).toList(growable: false);
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
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = accents.first);
    }
  }

  void _text(
      Canvas canvas, String value, Offset offset, double size, Color color,
      {double maxWidth = 80}) {
    final painter = TextPainter(
      text:
          TextSpan(text: value, style: TextStyle(fontSize: size, color: color)),
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
    if ((value - value.roundToDouble()).abs() < 0.001)
      return value.round().toString();
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _WesiAiChartPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.foreground != foreground ||
      oldDelegate.muted != muted;
}
