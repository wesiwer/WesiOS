import 'dart:convert';

enum WesiAiContentBlockType {
  knowledge,
  table,
  chart,
  diagram,
  media,
  confirmation,
}

/// Presentation payload attached to a Wesi AI message.
///
/// The protocol is deliberately data-only. A model can describe a table,
/// chart, diagram or generated asset, but it cannot send executable Flutter,
/// HTML or JavaScript into the client.
class WesiAiContentBlock {
  final WesiAiContentBlockType type;
  final Map<String, dynamic> data;

  const WesiAiContentBlock({required this.type, required this.data});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'data': data,
      };

  static WesiAiContentBlock? fromJson(Object? value) {
    if (value is! Map) return null;
    final raw = Map<String, dynamic>.from(value);
    final typeName = '${raw['type'] ?? ''}'.trim().toLowerCase();
    final data = raw['data'];
    if (data is! Map) return null;
    WesiAiContentBlockType? type;
    for (final item in WesiAiContentBlockType.values) {
      if (item.name == typeName) {
        type = item;
        break;
      }
    }
    if (type == null) return null;
    return _validated(type, Map<String, dynamic>.from(data));
  }

  static WesiAiContentBlock? _validated(
    WesiAiContentBlockType type,
    Map<String, dynamic> data,
  ) {
    switch (type) {
      case WesiAiContentBlockType.knowledge:
        final id = _text(data['articleId'], 160);
        final title = _text(data['title'], 240);
        if (id.isEmpty || title.isEmpty) return null;
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'articleId': id,
            'title': title,
            if (_text(data['excerpt'], 800).isNotEmpty)
              'excerpt': _text(data['excerpt'], 800),
            if (_text(data['section'], 80).isNotEmpty)
              'section': _text(data['section'], 80),
          },
        );

      case WesiAiContentBlockType.confirmation:
        final id = _text(data['id'], 180);
        final expiresAt = DateTime.tryParse(_text(data['expiresAt'], 80));
        final rawPreview = data['preview'];
        if (!RegExp(r'^wai_confirm_[A-Za-z0-9_-]{16,180}$').hasMatch(id) ||
            expiresAt == null ||
            rawPreview is! Map) {
          return null;
        }
        final preview = Map<String, dynamic>.from(rawPreview);
        if (_text(preview['risk'], 24) != 'DESTRUCTIVE') return null;
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'id': id,
            'expiresAt': expiresAt.toUtc().toIso8601String(),
            'preview': <String, dynamic>{
              'tool': _text(preview['tool'], 120),
              'module': _text(preview['module'], 80),
              'action': _text(preview['action'], 80),
              'risk': 'DESTRUCTIVE',
              if (_text(preview['targetId'], 180).isNotEmpty)
                'targetId': _text(preview['targetId'], 180),
            },
          },
        );

      case WesiAiContentBlockType.table:
        final columns = _strings(data['columns'], 20, 120);
        if (columns.isEmpty) return null;
        final rows = <List<String>>[];
        final rawRows = data['rows'];
        if (rawRows is List) {
          for (final row in rawRows.take(100)) {
            if (row is! List) continue;
            final cells = row
                .take(columns.length)
                .map((cell) => _text(cell, 500))
                .toList(growable: false);
            rows.add(List<String>.generate(
              columns.length,
              (i) => i < cells.length ? cells[i] : '',
              growable: false,
            ));
          }
        }
        if (rows.isEmpty) return null;
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'title': _text(data['title'], 240),
            'columns': columns,
            'rows': rows,
          },
        );

      case WesiAiContentBlockType.chart:
        const supported = <String>{'line', 'bar', 'pie', 'scatter'};
        final chartType = _text(data['chartType'], 20).toLowerCase();
        if (!supported.contains(chartType)) return null;
        final labels = _strings(data['labels'], 80, 80);
        final series = <Map<String, dynamic>>[];
        final rawSeries = data['series'];
        if (rawSeries is List) {
          for (final rawItem in rawSeries.take(12)) {
            if (rawItem is! Map) continue;
            final item = Map<String, dynamic>.from(rawItem);
            final values = _numbers(item['values'], 200);
            if (values.isEmpty) continue;
            series.add(<String, dynamic>{
              'name': _text(item['name'], 120),
              'values': values,
            });
          }
        }
        if (series.isEmpty) return null;
        if (chartType != 'scatter' && labels.isEmpty) return null;
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'title': _text(data['title'], 240),
            'chartType': chartType,
            'labels': labels,
            'series': series,
            if (_text(data['xLabel'], 100).isNotEmpty)
              'xLabel': _text(data['xLabel'], 100),
            if (_text(data['yLabel'], 100).isNotEmpty)
              'yLabel': _text(data['yLabel'], 100),
          },
        );

      case WesiAiContentBlockType.diagram:
        final nodes = <Map<String, String>>[];
        final nodeIds = <String>{};
        final rawNodes = data['nodes'];
        if (rawNodes is List) {
          for (final rawNode in rawNodes.take(40)) {
            if (rawNode is! Map) continue;
            final map = Map<String, dynamic>.from(rawNode);
            final id = _text(map['id'], 80);
            final label = _text(map['label'], 220);
            if (id.isEmpty || label.isEmpty || !nodeIds.add(id)) continue;
            nodes.add(<String, String>{'id': id, 'label': label});
          }
        }
        if (nodes.isEmpty) return null;
        final edges = <Map<String, String>>[];
        final rawEdges = data['edges'];
        if (rawEdges is List) {
          for (final rawEdge in rawEdges.take(80)) {
            if (rawEdge is! Map) continue;
            final map = Map<String, dynamic>.from(rawEdge);
            final from = _text(map['from'], 80);
            final to = _text(map['to'], 80);
            if (!nodeIds.contains(from) || !nodeIds.contains(to)) continue;
            edges.add(<String, String>{
              'from': from,
              'to': to,
              'label': _text(map['label'], 120),
            });
          }
        }
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'title': _text(data['title'], 240),
            'nodes': nodes,
            'edges': edges,
          },
        );

      case WesiAiContentBlockType.media:
        const supported = <String>{'image', 'video', 'audio', 'music'};
        final mediaType = _text(data['mediaType'], 20).toLowerCase();
        if (!supported.contains(mediaType)) return null;
        final status = _text(data['status'], 24).toLowerCase();
        final url = _safeUrl(data['url']);
        // Pending/failed generation may legitimately have no URL yet.
        if (url.isEmpty && status != 'pending' && status != 'failed')
          return null;
        return WesiAiContentBlock(
          type: type,
          data: <String, dynamic>{
            'mediaType': mediaType,
            'title': _text(data['title'], 240),
            'prompt': _text(data['prompt'], 2000),
            'status': status.isEmpty ? 'ready' : status,
            if (url.isNotEmpty) 'url': url,
            if (_safeUrl(data['thumbnailUrl']).isNotEmpty)
              'thumbnailUrl': _safeUrl(data['thumbnailUrl']),
            if (_text(data['mimeType'], 100).isNotEmpty)
              'mimeType': _text(data['mimeType'], 100),
          },
        );
    }
  }

  static String _text(Object? value, int max) {
    final text = '${value ?? ''}'.trim();
    return text.length <= max ? text : text.substring(0, max);
  }

  static List<String> _strings(Object? value, int maxItems, int maxLength) {
    if (value is! List) return const <String>[];
    return value
        .take(maxItems)
        .map((item) => _text(item, maxLength))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<double> _numbers(Object? value, int maxItems) {
    if (value is! List) return const <double>[];
    final out = <double>[];
    for (final item in value.take(maxItems)) {
      final n = item is num ? item.toDouble() : double.tryParse('$item');
      if (n != null && n.isFinite) out.add(n);
    }
    return out;
  }

  static String _safeUrl(Object? value) {
    final raw = _text(value, 4096);
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return '';
    if (uri.scheme != 'https' && uri.scheme != 'http') return '';
    return uri.toString();
  }
}

class WesiAiParsedContent {
  final String text;
  final List<WesiAiContentBlock> blocks;

  const WesiAiParsedContent({required this.text, required this.blocks});
}

/// Turns verified tool results and data-only presentation fences into blocks.
class WesiAiContentParser {
  static const int maxBlocks = 20;

  static WesiAiParsedContent parse({
    required String answer,
    Object? toolResults,
  }) {
    final blocks = <WesiAiContentBlock>[];
    _appendVerifiedToolBlocks(blocks, toolResults);

    var visible = answer;
    final fence = RegExp(
      r'```wesi-(table|chart|diagram|media)\s*\n([\s\S]*?)```',
      caseSensitive: false,
    );
    visible = visible.replaceAllMapped(fence, (match) {
      if (blocks.length >= maxBlocks) return '';
      final kind = (match.group(1) ?? '').toLowerCase();
      final rawJson = match.group(2) ?? '';
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          final block = WesiAiContentBlock.fromJson(<String, dynamic>{
            'type': kind,
            'data': Map<String, dynamic>.from(decoded),
          });
          if (block != null) blocks.add(block);
        }
      } catch (_) {
        // Invalid model-authored presentation data is ignored, never executed.
      }
      return '';
    });

    return WesiAiParsedContent(
      text: visible.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(),
      blocks: blocks.take(maxBlocks).toList(growable: false),
    );
  }

  static void _appendVerifiedToolBlocks(
    List<WesiAiContentBlock> blocks,
    Object? rawToolResults,
  ) {
    if (rawToolResults is! List) return;
    final seenKnowledge = <String>{};
    for (final raw in rawToolResults) {
      if (blocks.length >= maxBlocks || raw is! Map) break;
      final item = Map<String, dynamic>.from(raw);
      if (item['verified'] != true) continue;
      if ('${item['code'] ?? ''}' == 'CONFIRMATION_REQUIRED') {
        final rawConfirmation = item['confirmation'];
        if (rawConfirmation is Map && blocks.length < maxBlocks) {
          final block = WesiAiContentBlock.fromJson(<String, dynamic>{
            'type': 'confirmation',
            'data': Map<String, dynamic>.from(rawConfirmation),
          });
          if (block != null) blocks.add(block);
        }
        continue;
      }
      if (item['ok'] != true) continue;
      final result = item['result'];
      if (result is! Map) continue;
      final resultMap = Map<String, dynamic>.from(result);

      // Presentation tools return one already server-validated data block.
      final rawContentBlock = resultMap['contentBlock'];
      if (rawContentBlock is Map && blocks.length < maxBlocks) {
        final block = WesiAiContentBlock.fromJson(rawContentBlock);
        if (block != null) blocks.add(block);
      }

      // Knowledge references are built only from the verified knowledge tool
      // result, never from an arbitrary article id authored by the model.
      if ('${item['tool'] ?? ''}' != 'knowledge_search') continue;
      final articles = resultMap['articles'];
      if (articles is! List) continue;
      for (final rawArticle in articles.take(8)) {
        if (blocks.length >= maxBlocks || rawArticle is! Map) break;
        final article = Map<String, dynamic>.from(rawArticle);
        final id = '${article['id'] ?? ''}'.trim();
        if (id.isEmpty || !seenKnowledge.add(id)) continue;
        final text = '${article['text'] ?? ''}'.trim();
        final excerpt =
            text.length <= 360 ? text : '${text.substring(0, 360)}…';
        final block = WesiAiContentBlock.fromJson(<String, dynamic>{
          'type': 'knowledge',
          'data': <String, dynamic>{
            'articleId': id,
            'title': '${article['title'] ?? ''}',
            'excerpt': excerpt,
            'section': '${article['section'] ?? ''}',
          },
        });
        if (block != null) blocks.add(block);
      }
    }
  }
}
