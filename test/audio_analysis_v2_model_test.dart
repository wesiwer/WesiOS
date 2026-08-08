import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/models/audio_vault_extended_models.dart';

void main() {
  test('AudioAnalysisReport v2 JSON roundtrip keeps extended metrics', () {
    final report = AudioAnalysisReport(
      analyzedAt: DateTime.utc(2026, 8, 9),
      sourcePath: '/tmp/test.wav',
      format: 'WAV PCM',
      sampleRate: 48000,
      bitDepth: 24,
      channels: 2,
      durationSeconds: 120,
      peakDbfs: -1.2,
      estimatedTruePeakDbtp: -1.0,
      rmsDbfs: -12,
      estimatedIntegratedLufs: -10,
      crestFactorDb: 10.8,
      stereoCorrelation: .65,
      dcOffset: .0001,
      clippedSamples: 0,
      headSilenceSeconds: .1,
      tailSilenceSeconds: 1.2,
      spectralBalance: const {'Bass 60–120': .2},
      insights: const [],
      platformChecks: const [
        AudioPlatformCheck(
          platform: 'Spotify · Normal',
          ok: true,
          summary: 'ok',
          basis: 'Official guidance',
          sourceLabel: 'Spotify Loudness normalization',
        ),
      ],
      score: 96,
      disclaimer: 'estimate',
      sourceBytes: 123456,
      sourceModifiedAtMs: 42,
      peakToLoudnessRatioDb: 9,
      estimatedLoudnessRangeLu: 3.2,
      estimatedMaxMomentaryLufs: -7.5,
      estimatedMaxShortTermLufs: -8.2,
      channelBalanceDb: .3,
      midSideRatioDb: -8,
      edgeSilencePercent: 1.1,
      clippedSamplesPerMillion: 0,
    );

    final restored = AudioAnalysisReport.fromJson(report.toJson());
    expect(restored.sourceBytes, 123456);
    expect(restored.peakToLoudnessRatioDb, 9);
    expect(restored.estimatedLoudnessRangeLu, 3.2);
    expect(restored.estimatedMaxMomentaryLufs, -7.5);
    expect(restored.channelBalanceDb, .3);
    expect(restored.platformChecks.single.basis, 'Official guidance');
    expect(restored.platformChecks.single.sourceLabel,
        'Spotify Loudness normalization');
  });

  test('old report JSON remains readable with safe v2 defaults', () {
    final restored = AudioAnalysisReport.fromJson({
      'analyzedAt': '2026-08-09T00:00:00Z',
      'sourcePath': 'old.wav',
      'format': 'WAV PCM',
      'sampleRate': 44100,
      'bitDepth': 16,
      'channels': 2,
      'durationSeconds': 60,
      'peakDbfs': -1,
      'estimatedTruePeakDbtp': -.8,
      'rmsDbfs': -12,
      'estimatedIntegratedLufs': -11,
      'crestFactorDb': 11,
      'stereoCorrelation': .7,
      'dcOffset': 0,
      'clippedSamples': 0,
      'headSilenceSeconds': 0,
      'tailSilenceSeconds': 0,
      'spectralBalance': <String, double>{},
      'insights': <dynamic>[],
      'platformChecks': <dynamic>[],
      'score': 90,
      'disclaimer': 'legacy',
    });

    expect(restored.sourceBytes, 0);
    expect(restored.sourceModifiedAtMs, 0);
    expect(restored.estimatedMaxMomentaryLufs, -120);
    expect(restored.midSideRatioDb, -120);
  });
}
