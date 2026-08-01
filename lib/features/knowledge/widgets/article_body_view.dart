import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../models/article_model.dart';
import '../services/knowledge_service.dart';

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
  late final QuillController _controller;

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
      config: QuillEditorConfig(
        padding: EdgeInsets.zero,
        showCursor: false,
        enableInteractiveSelection: true,
        embedBuilders: [
          _ImageEmbedBuilder(),
          _VideoEmbedBuilder(),
          _TableEmbedBuilder(),
        ],
        customStyles: DefaultStyles(
          h1: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
            const HorizontalSpacing(0, 0),
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
            const HorizontalSpacing(0, 0),
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
            const HorizontalSpacing(0, 0),
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
            const HorizontalSpacing(0, 0),
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
  Widget build(BuildContext context, EmbedContext embedContext) {
    final url = embedContext.node.value.data;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
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
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    String url = data;
    if (data is String && data.trim().startsWith('{')) {
      try {
        url = (jsonDecode(data) as Map)['url'] as String? ?? data;
      } catch (_) {}
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _InlineVideo(url: url.toString()),
    );
  }
}

class _TableEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'table';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data.toString();
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
  final String url;
  const _InlineVideo({required this.url});

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
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
      final uri = Uri.parse(widget.url);
      final c = VideoPlayerController.networkUrl(uri);
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
