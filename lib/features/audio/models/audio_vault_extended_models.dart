enum AudioIssueSeverity { info, warning, critical }

class AudioAiInsight {
  final AudioIssueSeverity severity;
  final String title;
  final String detail;
  final String? action;

  const AudioAiInsight({
    required this.severity,
    required this.title,
    required this.detail,
    this.action,
  });

  Map<String, dynamic> toJson() => {
        'severity': severity.name,
        'title': title,
        'detail': detail,
        'action': action,
      };

  factory AudioAiInsight.fromJson(Map<String, dynamic> json) => AudioAiInsight(
        severity: AudioIssueSeverity.values.firstWhere(
          (e) => e.name == json['severity'],
          orElse: () => AudioIssueSeverity.info,
        ),
        title: '${json['title'] ?? ''}',
        detail: '${json['detail'] ?? ''}',
        action: json['action'] as String?,
      );
}

class AudioPlatformCheck {
  final String platform;
  final bool ok;
  final String summary;
  final double? targetLufs;
  final double? maxTruePeakDbtp;
  final double? normalizationGainDb;

  const AudioPlatformCheck({
    required this.platform,
    required this.ok,
    required this.summary,
    this.targetLufs,
    this.maxTruePeakDbtp,
    this.normalizationGainDb,
  });

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'ok': ok,
        'summary': summary,
        'targetLufs': targetLufs,
        'maxTruePeakDbtp': maxTruePeakDbtp,
        'normalizationGainDb': normalizationGainDb,
      };

  factory AudioPlatformCheck.fromJson(Map<String, dynamic> json) =>
      AudioPlatformCheck(
        platform: '${json['platform'] ?? ''}',
        ok: json['ok'] == true,
        summary: '${json['summary'] ?? ''}',
        targetLufs: (json['targetLufs'] as num?)?.toDouble(),
        maxTruePeakDbtp: (json['maxTruePeakDbtp'] as num?)?.toDouble(),
        normalizationGainDb:
            (json['normalizationGainDb'] as num?)?.toDouble(),
      );
}

class AudioAnalysisReport {
  final DateTime analyzedAt;
  final String sourcePath;
  final String format;
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final double durationSeconds;
  final double peakDbfs;
  final double estimatedTruePeakDbtp;
  final double rmsDbfs;
  final double estimatedIntegratedLufs;
  final double crestFactorDb;
  final double stereoCorrelation;
  final double dcOffset;
  final int clippedSamples;
  final double headSilenceSeconds;
  final double tailSilenceSeconds;
  final Map<String, double> spectralBalance;
  final List<AudioAiInsight> insights;
  final List<AudioPlatformCheck> platformChecks;
  final int score;
  final String disclaimer;

  const AudioAnalysisReport({
    required this.analyzedAt,
    required this.sourcePath,
    required this.format,
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
    required this.durationSeconds,
    required this.peakDbfs,
    required this.estimatedTruePeakDbtp,
    required this.rmsDbfs,
    required this.estimatedIntegratedLufs,
    required this.crestFactorDb,
    required this.stereoCorrelation,
    required this.dcOffset,
    required this.clippedSamples,
    required this.headSilenceSeconds,
    required this.tailSilenceSeconds,
    required this.spectralBalance,
    required this.insights,
    required this.platformChecks,
    required this.score,
    required this.disclaimer,
  });

  Map<String, dynamic> toJson() => {
        'analyzedAt': analyzedAt.toIso8601String(),
        'sourcePath': sourcePath,
        'format': format,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'channels': channels,
        'durationSeconds': durationSeconds,
        'peakDbfs': peakDbfs,
        'estimatedTruePeakDbtp': estimatedTruePeakDbtp,
        'rmsDbfs': rmsDbfs,
        'estimatedIntegratedLufs': estimatedIntegratedLufs,
        'crestFactorDb': crestFactorDb,
        'stereoCorrelation': stereoCorrelation,
        'dcOffset': dcOffset,
        'clippedSamples': clippedSamples,
        'headSilenceSeconds': headSilenceSeconds,
        'tailSilenceSeconds': tailSilenceSeconds,
        'spectralBalance': spectralBalance,
        'insights': insights.map((e) => e.toJson()).toList(),
        'platformChecks': platformChecks.map((e) => e.toJson()).toList(),
        'score': score,
        'disclaimer': disclaimer,
      };

  factory AudioAnalysisReport.fromJson(Map<String, dynamic> json) =>
      AudioAnalysisReport(
        analyzedAt:
            DateTime.tryParse('${json['analyzedAt']}') ?? DateTime.now(),
        sourcePath: '${json['sourcePath'] ?? ''}',
        format: '${json['format'] ?? ''}',
        sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 0,
        bitDepth: (json['bitDepth'] as num?)?.toInt() ?? 0,
        channels: (json['channels'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
        peakDbfs: (json['peakDbfs'] as num?)?.toDouble() ?? -120,
        estimatedTruePeakDbtp:
            (json['estimatedTruePeakDbtp'] as num?)?.toDouble() ?? -120,
        rmsDbfs: (json['rmsDbfs'] as num?)?.toDouble() ?? -120,
        estimatedIntegratedLufs:
            (json['estimatedIntegratedLufs'] as num?)?.toDouble() ?? -120,
        crestFactorDb: (json['crestFactorDb'] as num?)?.toDouble() ?? 0,
        stereoCorrelation:
            (json['stereoCorrelation'] as num?)?.toDouble() ?? 1,
        dcOffset: (json['dcOffset'] as num?)?.toDouble() ?? 0,
        clippedSamples: (json['clippedSamples'] as num?)?.toInt() ?? 0,
        headSilenceSeconds:
            (json['headSilenceSeconds'] as num?)?.toDouble() ?? 0,
        tailSilenceSeconds:
            (json['tailSilenceSeconds'] as num?)?.toDouble() ?? 0,
        spectralBalance: (json['spectralBalance'] as Map? ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toDouble())),
        insights: (json['insights'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => AudioAiInsight.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        platformChecks: (json['platformChecks'] as List? ?? const [])
            .whereType<Map>()
            .map((e) =>
                AudioPlatformCheck.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        score: (json['score'] as num?)?.toInt() ?? 0,
        disclaimer: '${json['disclaimer'] ?? ''}',
      );
}

class BeatExtendedMeta {
  final String? abletonProjectPath;
  final AudioAnalysisReport? analysis;

  const BeatExtendedMeta({this.abletonProjectPath, this.analysis});

  BeatExtendedMeta copyWith({
    String? abletonProjectPath,
    bool clearAbletonProject = false,
    AudioAnalysisReport? analysis,
  }) =>
      BeatExtendedMeta(
        abletonProjectPath: clearAbletonProject
            ? null
            : (abletonProjectPath ?? this.abletonProjectPath),
        analysis: analysis ?? this.analysis,
      );

  Map<String, dynamic> toJson() => {
        'abletonProjectPath': abletonProjectPath,
        'analysis': analysis?.toJson(),
      };

  factory BeatExtendedMeta.fromJson(Map<String, dynamic> json) =>
      BeatExtendedMeta(
        abletonProjectPath: json['abletonProjectPath'] as String?,
        analysis: json['analysis'] is Map
            ? AudioAnalysisReport.fromJson(
                Map<String, dynamic>.from(json['analysis']))
            : null,
      );
}

class MusicLibraryTrack {
  final String id;
  final String title;
  final String path;
  final DateTime addedAt;

  const MusicLibraryTrack({
    required this.id,
    required this.title,
    required this.path,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'addedAt': addedAt.toIso8601String(),
      };

  factory MusicLibraryTrack.fromJson(Map<String, dynamic> json) =>
      MusicLibraryTrack(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        path: '${json['path'] ?? ''}',
        addedAt: DateTime.tryParse('${json['addedAt']}') ?? DateTime.now(),
      );
}
