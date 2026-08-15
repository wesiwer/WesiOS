import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../knowledge/knowledge_base_screen.dart';
import '../../knowledge/services/knowledge_service.dart';
import '../../team/services/team_service.dart';
import '../models/wesi_ai_chat_models.dart';
import '../models/wesi_ai_content_blocks.dart';
import '../wesi_ai_action_api.dart';

class WesiAiMessageContent extends StatelessWidget {
  final WesiAiMessage message;
  final bool animateText;

  const WesiAiMessageContent({
    super.key,
    required this.message,
    this.animateText = true,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <WesiAiContentBlock>[];
    final rawBlocks = message.metadata['blocks'];
    if (rawBlocks is List) {
      for (final raw in rawBlocks.take(WesiAiContentParser.maxBlocks)) {
        final block = WesiAiContentBlock.fromJson(raw);
        if (block != null) blocks.add(block);
      }
    }

    final assistant = message.author == WesiAiMessageAuthor.zane ||
        message.author == WesiAiMessageAuthor.nirvana;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.isNotEmpty)
          WesiAiTypewriterText(
            messageId: message.id,
            text: message.text,
            animate: animateText &&
                assistant &&
                message.metadata['transportStreaming'] != true &&
                message.metadata['transportStreamed'] != true,
          ),
        for (final block in blocks) ...[
          const SizedBox(height: 10),
          _BlockView(block: block),
        ],
      ],
    );
  }
}

/// Reveals a new AI reply rune-by-rune. Completed messages are remembered for
/// the lifetime of the process, so scrolling an old message back into view
/// does not restart the animation.
class WesiAiTypewriterText extends StatefulWidget {
  final String messageId;
  final String text;
  final bool animate;

  const WesiAiTypewriterText({
    super.key,
    required this.messageId,
    required this.text,
    required this.animate,
  });

  @override
  State<WesiAiTypewriterText> createState() => _WesiAiTypewriterTextState();
}

class _WesiAiTypewriterTextState extends State<WesiAiTypewriterText> {
  static final Set<String> _completed = <String>{};
  Timer? _timer;
  late List<int> _runes;
  int _visible = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant WesiAiTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.text != widget.text) {
      _timer?.cancel();
      _prepare();
    }
  }

  void _prepare() {
    _runes = widget.text.runes.toList(growable: false);
    if (!widget.animate ||
        _completed.contains(widget.messageId) ||
        _runes.isEmpty) {
      _visible = _runes.length;
      _completed.add(widget.messageId);
      return;
    }
    _visible = 0;
    final delay = _runes.length > 1600
        ? 2
        : _runes.length > 700
            ? 4
            : _runes.length > 250
                ? 7
                : 13;
    _timer = Timer.periodic(Duration(milliseconds: delay), (_) {
      if (!mounted) return;
      if (_visible >= _runes.length) {
        _timer?.cancel();
        _completed.add(widget.messageId);
        return;
      }
      setState(() => _visible++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = String.fromCharCodes(_runes.take(_visible));
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
    );
  }
}

class _BlockView extends StatelessWidget {
  final WesiAiContentBlock block;

  const _BlockView({required this.block});

  @override
  Widget build(BuildContext context) => switch (block.type) {
        WesiAiContentBlockType.knowledge => _KnowledgeBlock(data: block.data),
        WesiAiContentBlockType.table => _TableBlock(data: block.data),
        WesiAiContentBlockType.chart => _ChartBlock(data: block.data),
        WesiAiContentBlockType.diagram => _DiagramBlock(data: block.data),
        WesiAiContentBlockType.media => _MediaBlock(data: block.data),
        WesiAiContentBlockType.confirmation =>
          _ActionConfirmationBlock(data: block.data),
      };
}

class _ActionConfirmationBlock extends StatefulWidget {
  final Map<String, dynamic> data;

  const _ActionConfirmationBlock({required this.data});

  @override
  State<_ActionConfirmationBlock> createState() =>
      _ActionConfirmationBlockState();
}

class _ActionConfirmationBlockState extends State<_ActionConfirmationBlock> {
  bool _running = false;
  bool _terminal = false;
  bool _success = false;
  String? _message;

  Future<void> _confirm() async {
    if (_running || _terminal) return;
    final id = '${widget.data['id'] ?? ''}'.trim();
    final expiresAt = DateTime.tryParse('${widget.data['expiresAt'] ?? ''}');
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      setState(() {
        _terminal = true;
        _message = 'Срок подтверждения истёк. Повторите запрос к Wesi AI.';
      });
      return;
    }
    setState(() => _running = true);
    final result = await const WesiAiActionApi().confirm(id);
    if (!mounted) return;
    setState(() {
      _running = false;
      _success = result.ok;
      _message = result.ok
          ? 'Действие выполнено.'
          : (result.message ?? 'Не удалось выполнить действие.');
      _terminal = result.ok ||
          (result.code != null &&
              result.code != 'NETWORK' &&
              result.code != 'WAI_CONFIRMATION_BAD_RESPONSE');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewRaw = widget.data['preview'];
    final preview = previewRaw is Map
        ? Map<String, dynamic>.from(previewRaw)
        : const <String, dynamic>{};
    final module = '${preview['module'] ?? ''}'.trim();
    final action = '${preview['action'] ?? ''}'.trim();
    final target = '${preview['targetId'] ?? ''}'.trim();
    final expiresAt = DateTime.tryParse('${widget.data['expiresAt'] ?? ''}');
    final expired =
        expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc());
    final disabled = _running || _terminal || expired;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Требуется подтверждение действия',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (module.isNotEmpty) 'Раздел: $module',
                if (action.isNotEmpty) 'Действие: $action',
                if (target.isNotEmpty) 'Объект: $target',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (_message != null) ...[
              Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _success
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: disabled ? null : _confirm,
              icon: _running
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(
                _success
                    ? 'Выполнено'
                    : expired
                        ? 'Подтверждение истекло'
                        : 'Подтвердить действие',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _KnowledgeBlock({required this.data});

  Future<void> _open(BuildContext context) async {
    final id = '${data['articleId'] ?? ''}'.trim();
    if (id.isEmpty) return;
    final article = await KnowledgeService.getById(id);
    if (article == null || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Статья больше не найдена в Базе знаний')),
        );
      }
      return;
    }

    final permissions = TeamService.currentPermissions;
    final allowed = permissions.knowledgeAll ||
        permissions.allowsArticle(article.id) ||
        (article.parentId != null &&
            permissions.allowsArticle(article.parentId!));
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступа к этой статье')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ArticleScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final excerpt = '${data['excerpt'] ?? ''}'.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data['title'] ?? ''}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (excerpt.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        excerpt,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      'Открыть статью в Базе знаний',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TableBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = List<String>.from(data['columns'] as List? ?? const []);
    final rows = (data['rows'] as List? ?? const [])
        .whereType<List>()
        .map((row) => row.map((cell) => '$cell').toList(growable: false))
        .toList(growable: false);
    final title = '${data['title'] ?? ''}'.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 80,
                columns: [
                  for (final column in columns)
                    DataColumn(
                      label: Text(
                        column,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        for (var i = 0; i < columns.length; i++)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(i < row.length ? row[i] : ''),
                            ),
                          ),
                      ],
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

class _ChartBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ChartBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = '${data['title'] ?? ''}'.trim();
    final chartType = '${data['chartType'] ?? 'line'}';
    final labels = List<String>.from(data['labels'] as List? ?? const []);
    final series = (data['series'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 240,
              width: double.infinity,
              child: CustomPaint(
                painter: _AiChartPainter(
                  chartType: chartType,
                  labels: labels,
                  series: series,
                  colorScheme: theme.colorScheme,
                  textColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (series.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < series.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _chartColor(theme.colorScheme, i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text('${series[i]['name'] ?? 'Серия ${i + 1}'}'),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiChartPainter extends CustomPainter {
  final String chartType;
  final List<String> labels;
  final List<Map<String, dynamic>> series;
  final ColorScheme colorScheme;
  final Color textColor;

  _AiChartPainter({
    required this.chartType,
    required this.labels,
    required this.series,
    required this.colorScheme,
    required this.textColor,
  });

  List<double> _values(Map<String, dynamic> item) =>
      (item['values'] as List? ?? const [])
          .map((value) =>
              value is num ? value.toDouble() : double.tryParse('$value'))
          .whereType<double>()
          .where((value) => value.isFinite)
          .toList(growable: false);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    if (chartType == 'pie') {
      _paintPie(canvas, size);
      return;
    }
    if (chartType == 'scatter') {
      _paintCartesian(canvas, size, scatter: true);
      return;
    }
    _paintCartesian(canvas, size, bars: chartType == 'bar');
  }

  void _paintCartesian(
    Canvas canvas,
    Size size, {
    bool bars = false,
    bool scatter = false,
  }) {
    const left = 42.0;
    const top = 10.0;
    const right = 10.0;
    const bottom = 34.0;
    final rect =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (rect.width <= 0 || rect.height <= 0) return;

    final all = <double>[];
    for (final item in series) {
      all.addAll(_values(item));
    }
    if (all.isEmpty) return;
    var minValue = all.reduce(math.min);
    var maxValue = all.reduce(math.max);
    if (minValue > 0) minValue = 0;
    if (maxValue < 0) maxValue = 0;
    if ((maxValue - minValue).abs() < 1e-9) maxValue = minValue + 1;

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = rect.top + rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      final value = maxValue - (maxValue - minValue) * i / 4;
      _label(
          canvas, _compact(value), Offset(0, y - 7), left - 6, TextAlign.right);
    }

    final maxPoints =
        series.map(_values).fold<int>(0, (a, b) => math.max(a, b.length));
    if (maxPoints == 0) return;
    double xAt(int index) => maxPoints <= 1
        ? rect.center.dx
        : rect.left + rect.width * index / (maxPoints - 1);
    double yAt(double value) =>
        rect.bottom - (value - minValue) / (maxValue - minValue) * rect.height;

    if (bars) {
      final groupWidth = rect.width / math.max(maxPoints, 1);
      final barWidth =
          math.max(2.0, groupWidth * 0.72 / math.max(series.length, 1));
      for (var s = 0; s < series.length; s++) {
        final values = _values(series[s]);
        final paint = Paint()..color = _chartColor(colorScheme, s);
        for (var i = 0; i < values.length; i++) {
          final center = rect.left + groupWidth * (i + 0.5);
          final x = center - groupWidth * 0.36 + barWidth * s;
          final zeroY = yAt(0);
          final valueY = yAt(values[i]);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(x, math.min(zeroY, valueY), x + barWidth,
                  math.max(zeroY, valueY)),
              const Radius.circular(3),
            ),
            paint,
          );
        }
      }
    } else {
      for (var s = 0; s < series.length; s++) {
        final values = _values(series[s]);
        final paint = Paint()
          ..color = _chartColor(colorScheme, s)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke;
        final fill = Paint()..color = _chartColor(colorScheme, s);
        final path = Path();
        for (var i = 0; i < values.length; i++) {
          final p = Offset(xAt(i), yAt(values[i]));
          if (scatter) {
            canvas.drawCircle(p, 3.6, fill);
          } else if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        if (!scatter && values.isNotEmpty) canvas.drawPath(path, paint);
      }
    }

    final labelCount = labels.length;
    if (labelCount > 0) {
      final step = math.max(1, (labelCount / 6).ceil());
      for (var i = 0; i < labelCount && i < maxPoints; i += step) {
        _label(
          canvas,
          labels[i],
          Offset(xAt(i) - 34, rect.bottom + 7),
          68,
          TextAlign.center,
        );
      }
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final values = _values(series.first).map((v) => math.max(0.0, v)).toList();
    if (values.isEmpty) return;
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2 - 4);
    final radius = math.min(size.width, size.height) * 0.36;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      final paint = Paint()
        ..color = _chartColor(colorScheme, i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.52;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.68),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
    _label(canvas, '100%', Offset(center.dx - 28, center.dy - 9), 56,
        TextAlign.center);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    double width,
    TextAlign align,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: textColor),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  String _compact(double value) {
    final abs = value.abs();
    if (abs >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
    if (abs >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.abs() >= 10
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _AiChartPainter oldDelegate) =>
      chartType != oldDelegate.chartType ||
      labels != oldDelegate.labels ||
      series != oldDelegate.series ||
      colorScheme != oldDelegate.colorScheme;
}

Color _chartColor(ColorScheme scheme, int index) {
  final colors = <Color>[
    scheme.primary,
    scheme.secondary,
    scheme.tertiary,
    scheme.error,
    scheme.primaryContainer,
    scheme.secondaryContainer,
  ];
  return colors[index % colors.length];
}

class _DiagramBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DiagramBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = '${data['title'] ?? ''}'.trim();
    final nodes = (data['nodes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final edges = (data['edges'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final nodeById = <String, Map<String, dynamic>>{
      for (final node in nodes) '${node['id']}': node,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
            ],
            for (var i = 0; i < nodes.length; i++) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  '${nodes[i]['label'] ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (i < nodes.length - 1) ...[
                const SizedBox(height: 4),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.arrow_downward,
                          size: 18, color: theme.colorScheme.primary),
                      ...edges
                          .where((edge) =>
                              '${edge['from']}' == '${nodes[i]['id']}' &&
                              nodeById.containsKey('${edge['to']}'))
                          .take(2)
                          .map(
                            (edge) => '${edge['label'] ?? ''}'.trim().isEmpty
                                ? const SizedBox.shrink()
                                : Text(
                                    '${edge['label']}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaBlock extends StatelessWidget {
  final Map<String, dynamic> data;

  const _MediaBlock({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = '${data['mediaType'] ?? ''}';
    final status = '${data['status'] ?? 'ready'}';
    final url = '${data['url'] ?? ''}';
    final title = '${data['title'] ?? ''}'.trim();

    if (status != 'ready' || url.isEmpty) {
      return Card(
        child: ListTile(
          leading: status == 'failed'
              ? const Icon(Icons.error_outline)
              : const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
          title: Text(title.isEmpty ? 'Генерация $type' : title),
          subtitle: Text(status == 'failed'
              ? 'Генерация не завершилась'
              : 'Генерируется…'),
        ),
      );
    }

    return switch (type) {
      'image' => _ImageMedia(url: url, title: title),
      'video' => _VideoMedia(url: url, title: title),
      'audio' ||
      'music' =>
        _AudioMedia(url: url, title: title, music: type == 'music'),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ImageMedia extends StatelessWidget {
  final String url;
  final String title;

  const _ImageMedia({required this.url, required this.title});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              url,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 140,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
}

class _AudioMedia extends StatefulWidget {
  final String url;
  final String title;
  final bool music;

  const _AudioMedia({
    required this.url,
    required this.title,
    required this.music,
  });

  @override
  State<_AudioMedia> createState() => _AudioMediaState();
}

class _AudioMediaState extends State<_AudioMedia> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(widget.url));
      if (mounted) setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(widget.music ? Icons.music_note : Icons.graphic_eq),
          title: Text(widget.title.isEmpty
              ? (widget.music ? 'Музыка Wesi AI' : 'Аудио Wesi AI')
              : widget.title),
          trailing: IconButton.filledTonal(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
        ),
      );
}

class _VideoMedia extends StatefulWidget {
  final String url;
  final String title;

  const _VideoMedia({required this.url, required this.title});

  @override
  State<_VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<_VideoMedia> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.video_file_outlined),
          title: Text(widget.title.isEmpty ? 'Видео Wesi AI' : widget.title),
          subtitle: const Text('Не удалось открыть inline-превью'),
          trailing: IconButton(
            onPressed: () => launchUrl(Uri.parse(widget.url)),
            icon: const Icon(Icons.open_in_new),
          ),
        ),
      );
    }
    if (controller == null) {
      return const Card(
        child: SizedBox(
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 16 / 9
                : controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                IconButton.filled(
                  onPressed: () {
                    setState(() {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    });
                  },
                  icon: Icon(controller.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow),
                ),
              ],
            ),
          ),
          if (widget.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
