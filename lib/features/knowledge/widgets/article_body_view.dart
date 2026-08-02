import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_theme.dart';
import '../models/article_model.dart';
import '../services/knowledge_service.dart';
import 'dart:io';

/// Рендер тела статьи: Quill Delta JSON или legacy plain/Markdown.
///
/// Картинки, видео и ссылки остаются **в том месте**, куда их вставили
/// в редакторе — не выносятся в конец и не на отдельную вкладку.
class ArticleBodyView extends StatelessWidget {
  final ArticleModel article;
  final void Function(String route)? onInternalRoute;

  const ArticleBodyView({
    super.key,
    required this.article,
    this.onInternalRoute,
  });

  @override
  Widget build(BuildContext context) {
    if (article.isRichBody) {
      return _QuillBody(
        body: article.body,
        onInternalRoute: onInternalRoute,
      );
    }
    return _LegacyMarkdownBody(body: article.body);
  }
}

class _QuillBody extends StatefulWidget {
  final String body;
  final void Function(String route)? onInternalRoute;

  const _QuillBody({required this.body, this.onInternalRoute});

  @override
  State<_QuillBody> createState() => _QuillBodyState();
}

class _QuillBodyState extends State<_QuillBody> {
  late QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _controllerFromBody(widget.body);
  }

  @override
  void didUpdateWidget(covariant _QuillBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      _controller.dispose();
      _controller = _controllerFromBody(widget.body);
    }
  }

  QuillController _controllerFromBody(String body) {
    try {
      final json = jsonDecode(body);
      final doc = Document.fromJson(json is List ? json : (json['ops'] ?? []));
      return QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      return QuillController(
        document: Document()..insert(0, body),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onLaunch(String? url) async {
    if (url == null || url.isEmpty) return;
    if (url.startsWith('wesios://')) {
      final path = url.substring('wesios://'.length);
      if (path.startsWith('article/')) {
        final id = path.substring('article/'.length);
        final a = await KnowledgeService.getById(id);
        if (a != null && mounted) {
          // Открыть статью поверх — вызывающий экран может заменить.
          widget.onInternalRoute?.call('article:$id');
        }
        return;
      }
      if (path.startsWith('route/')) {
        final route = path.substring('route/'.length);
        widget.onInternalRoute?.call(route.startsWith('/') ? route : '/$route');
        return;
      }
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuillEditor.basic(
      controller: _controller,
      configurations: QuillEditorConfigurations(
        padding: EdgeInsets.zero,
        showCursor: false,
        enableInteractiveSelection: true,
        embedBuilders: [
          _ImageEmbedBuilder(),
          _VideoEmbedBuilder(),
          _AudioEmbedBuilder(),
          _ChartEmbedBuilder(),
          _TableEmbedBuilder(),
        ],
        customStyles: DefaultStyles(
          h1: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
            const VerticalSpacing(10, 6),
            const VerticalSpacing(0, 0),
            null,
          ),
          h2: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentOrange,
            ),
            const VerticalSpacing(10, 4),
            const VerticalSpacing(0, 0),
            null,
          ),
          h3: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            const VerticalSpacing(8, 4),
            const VerticalSpacing(0, 0),
            null,
          ),
          paragraph: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 14,
              height: 1.55,
              color: AppTheme.textSecondary,
            ),
            const VerticalSpacing(0, 6),
            const VerticalSpacing(0, 0),
            null,
          ),
          link: TextStyle(
            color: AppTheme.accentOrange,
            decoration: TextDecoration.underline,
          ),
        ),
        onLaunchUrl: _onLaunch,
      ),
    );
  }
}

// ─── Embeds ─────────────────────────────────────────────────────────────────

class _ImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final source = node.value.data.toString();
    final isLocal = !source.startsWith('http') && File(source).existsSync();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isLocal
            ? Image.file(
                File(source),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _broken(
                  Icons.broken_image_outlined,
                  'Image',
                ),
              )
            : Image.network(
                source,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _broken(
                  Icons.broken_image_outlined,
                  'Image',
                ),
              ),
      ),
    );
  }
}

class _VideoEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'video';

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final data = node.value.data;
    String source = data is String ? data : data.toString();
    if (source.trim().startsWith('{')) {
      try {
        source = (jsonDecode(source) as Map)['url'] as String? ?? source;
      } catch (_) {}
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _InlineVideo(source: source),
    );
  }
}

class _AudioEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'audio';

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final source = node.value.data.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _InlineAudio(source: source),
    );
  }
}

class _ChartEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'chart';

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final data = node.value.data.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _InlineChart(data: data),
    );
  }
}

class _TableEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'table';

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final raw = node.value.data.toString();
    List<List<String>> rows = [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        rows = decoded
            .map((r) => (r as List).map((c) => c.toString()).toList())
            .toList();
      }
    } catch (_) {
      // CSV-like: lines with |
      for (final line in raw.split('\n')) {
        if (line.trim().isEmpty) continue;
        rows.add(line.split('|').map((c) => c.trim()).toList());
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: AppTheme.glassBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: i == 0
                      ? AppTheme.surface.withOpacity(0.8)
                      : AppTheme.surface.withOpacity(0.35),
                ),
                children: [
                  for (final cell in rows[i])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(
                        cell,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              i == 0 ? FontWeight.w700 : FontWeight.w400,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InlineVideo extends StatefulWidget {
  final String source;
  const _InlineVideo({required this.source});

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineAudio extends StatefulWidget {
  final String source;
  const _InlineAudio({required this.source});

  @override
  State<_InlineAudio> createState() => _InlineAudioState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final isLocal = !widget.source.startsWith('http') && File(widget.source).existsSync();
      final c = isLocal
          ? VideoPlayerController.file(File(widget.source))
          : VideoPlayerController.networkUrl(Uri.parse(widget.source));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _broken(Icons.videocam_off_outlined, 'Video');
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CircularProgressIndicator(
            color: AppTheme.accentOrange.withOpacity(0.5)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            Material(
              color: Colors.black26,
              child: IconButton(
                iconSize: 48,
                icon: Icon(
                  c.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAudioState extends State<_InlineAudio> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLocal = false;

  @override
  void initState() {
    super.initState();
    _isLocal = !widget.source.startsWith('http') && File(widget.source).existsSync();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      if (_isLocal) {
        await _player.setSource(DeviceFileSource(widget.source));
      } else {
        await _player.setSource(UrlSource(widget.source));
      }
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      });
    } catch (e) {
      debugPrint('Audio init error: $e');
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _seek(double value) async {
    final position = Duration(milliseconds: (value * _duration.inMilliseconds).toInt());
    await _player.seek(position);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: AppTheme.accent,
              size: 36,
            ),
            onPressed: _togglePlay,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: _seek,
                  activeColor: AppTheme.accent,
                  inactiveColor: AppTheme.glassBorder,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineChart extends StatelessWidget {
  final String data;
  const _InlineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> chartData;
    try {
      chartData = jsonDecode(data);
    } catch (_) {
      return _broken(Icons.bar_chart, 'Chart');
    }
    final type = chartData['type'] as String? ?? 'bar';
    final title = chartData['title'] as String? ?? '';
    final source = chartData['source'] as String? ?? 'manual';

    List<double> values;
    List<String> labels;

    if (source == 'manual') {
      values = (chartData['data'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList();
      labels = (chartData['labels'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    } else {
      // Linked data — заглушка с демо-данными (в будущем: подгрузка из сервисов)
      final linked = _getLinkedData(source);
      values = linked['data'] as List<double>;
      labels = linked['labels'] as List<String>;
    }

    if (values.isEmpty) return _broken(Icons.bar_chart, 'Chart');

    final barGroups = values.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [BarChartRodData(toY: e.value, color: AppTheme.accent, width: 16)],
      );
    }).toList();

    Widget chartWidget;
    switch (type) {
      case 'line':
        chartWidget = LineChart(
          LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.glassBorder)),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(labels.length > v.toInt() ? labels[v.toInt()] : '', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                color: AppTheme.accent,
                barWidth: 2,
                dotData: FlDotData(show: true),
              ),
            ],
          ),
        );
        break;
      case 'pie':
        final total = values.fold<double>(0, (s, v) => s + v);
        chartWidget = PieChart(
          PieChartData(
            sections: values.asMap().entries.map((e) {
              final pct = total > 0 ? e.value / total : 0;
              return PieChartSectionData(
                value: e.value,
                title: '${(pct * 100).toStringAsFixed(0)}%',
                color: [AppTheme.accent, AppTheme.accentGreen, AppTheme.accentOrange, AppTheme.accentRed, AppTheme.lightAccentBlue][e.key % 5],
                radius: 60,
                titleStyle: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        );
        break;
      case 'area':
        chartWidget = LineChart(
          LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.glassBorder)),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(labels.length > v.toInt() ? labels[v.toInt()] : '', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                color: AppTheme.accent,
                barWidth: 2,
                belowBarData: BarAreaData(show: true, color: AppTheme.accent.withOpacity(0.2)),
                dotData: FlDotData(show: false),
              ),
            ],
          ),
        );
        break;
      case 'bar':
      default:
        chartWidget = BarChart(
          BarChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.glassBorder)),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(labels.length > v.toInt() ? labels[v.toInt()] : '', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: AppTheme.textMuted)))),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
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
              child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
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

  static Map<String, List<dynamic>> _getLinkedData(String source) {
    switch (source) {
      case 'forecast':
        return {
          'data': [120.0, 135.0, 128.0, 155.0, 170.0, 185.0, 195.0, 210.0],
          'labels': ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8'],
        };
      case 'analytics':
        return {
          'data': [45.0, 62.0, 38.0, 75.0, 55.0, 88.0],
          'labels': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'],
        };
      case 'treasury':
        return {
          'data': [5000.0, 4200.0, 6800.0, 5500.0, 7200.0, 8100.0, 7800.0],
          'labels': ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл'],
        };
      default:
        return {'data': <double>[], 'labels': <String>[]};
    }
  }
}

Widget _broken(IconData icon, String label) => Container(
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
          Icon(icon, color: AppTheme.textMuted),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );

// ─── Legacy markdown ────────────────────────────────────────────────────────

class _LegacyMarkdownBody extends StatelessWidget {
  final String body;
  const _LegacyMarkdownBody({required this.body});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(3),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentOrange)),
        ));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(line.substring(2),
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
        ));
        continue;
      }
      if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•', style: TextStyle(color: AppTheme.accentOrange)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(line.substring(2).replaceAll('**', ''),
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ));
        continue;
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(line.replaceAll('**', ''),
            style: TextStyle(
                fontSize: 13, height: 1.55, color: AppTheme.textSecondary)),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
