class WesiMediaLocalRequestSanitizer {
  static const Set<String> workflows = <String>{
    'imageGenerate',
    'imageEdit',
    'imageReference',
    'musicGenerate',
    'musicStems',
    'musicRegenerateStem',
    'musicMix',
    'musicExport',
    'videoGenerate',
    'videoCompose',
    'videoVoice',
    'videoSfx',
    'videoSubtitles',
  };

  static const Map<String, String> _workflowMediaType = <String, String>{
    'imageGenerate': 'image',
    'imageEdit': 'image',
    'imageReference': 'image',
    'musicGenerate': 'music',
    'musicStems': 'music',
    'musicRegenerateStem': 'music',
    'musicMix': 'music',
    'musicExport': 'music',
    'videoGenerate': 'video',
    'videoCompose': 'video',
    'videoVoice': 'video',
    'videoSfx': 'video',
    'videoSubtitles': 'video',
  };

  static const Map<String, (int, int)> _inputBounds =
      <String, (int, int)>{
    'imageGenerate': (0, 0),
    'imageEdit': (1, 1),
    'imageReference': (1, 1),
    'musicGenerate': (0, 0),
    'musicStems': (1, 1),
    'musicRegenerateStem': (1, 1),
    'musicMix': (2, 4),
    'musicExport': (1, 4),
    'videoGenerate': (0, 0),
    'videoCompose': (1, 4),
    'videoVoice': (2, 2),
    'videoSfx': (1, 1),
    'videoSubtitles': (1, 1),
  };

  static const Set<String> _forbiddenPathOptionKeys = <String>{
    'input',
    'inputs',
    'inputPath',
    'inputPaths',
    'path',
    'paths',
    'outputPath',
  };

  const WesiMediaLocalRequestSanitizer._();

  static Map<String, dynamic>? sanitize(Map<String, dynamic> raw) {
    final mediaType = '${raw['mediaType'] ?? ''}'.trim().toLowerCase();
    if (!const <String>{'image', 'music', 'video'}.contains(mediaType)) {
      return null;
    }

    final prompt = '${raw['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty || prompt.length > 12000) return null;

    final rawOptions = raw['options'];
    final options = <String, dynamic>{};
    if (rawOptions is Map) {
      for (final entry in rawOptions.entries.take(16)) {
        final key = '${entry.key}'.trim();
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9]{0,39}$').hasMatch(key)) continue;
        if (_forbiddenPathOptionKeys.contains(key)) continue;
        final value = entry.value;
        if (value is String && value.length <= 80) options[key] = value;
        if (value is num || value is bool) options[key] = value;
      }
    }

    final explicitWorkflow =
        '${raw['workflow'] ?? options['workflow'] ?? ''}'.trim();
    final workflow = explicitWorkflow.isNotEmpty
        ? explicitWorkflow
        : switch (mediaType) {
            'image' => 'imageGenerate',
            'music' => 'musicGenerate',
            'video' => 'videoGenerate',
            _ => '',
          };
    if (!workflows.contains(workflow) ||
        _workflowMediaType[workflow] != mediaType) {
      return null;
    }

    final indexes = _sanitizeIndexes(raw['attachmentIndexes']);
    if (indexes == null) return null;
    final bounds = _inputBounds[workflow]!;
    if (indexes.length < bounds.$1 || indexes.length > bounds.$2) return null;

    final rawTitle = '${raw['title'] ?? ''}'.trim();
    final title =
        rawTitle.length <= 240 ? rawTitle : rawTitle.substring(0, 240);
    options['workflow'] = workflow;

    return <String, dynamic>{
      'mediaType': mediaType,
      'workflow': workflow,
      'title': title,
      'prompt': prompt,
      'attachmentIndexes': indexes,
      'options': options,
    };
  }

  static List<int>? _sanitizeIndexes(Object? raw) {
    if (raw == null) return const <int>[];
    if (raw is! List || raw.length > 4) return null;
    final seen = <int>{};
    final out = <int>[];
    for (final value in raw) {
      final number = value is num ? value : int.tryParse('$value');
      if (number == null) return null;
      final index = number.toInt();
      if (number != index || index < 0 || index > 3 || !seen.add(index)) {
        return null;
      }
      out.add(index);
    }
    return out;
  }
}
