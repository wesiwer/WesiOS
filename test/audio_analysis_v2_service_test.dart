import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/audio/services/audio_analysis_v2_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Quick Analysis v2 analyzes a real synthetic PCM WAV', () async {
    final dir = await Directory.systemTemp.createTemp('wesios_audio_v2_');
    final file = File('${dir.path}${Platform.pathSeparator}sine.wav');
    try {
      await file.writeAsBytes(_pcm16MonoSineWav(
        sampleRate: 48000,
        seconds: .6,
        amplitude: .25,
        frequency: 440,
      ));

      final report = await AudioAnalysisV2Service.analyzeWav(file.path);

      expect(report.sampleRate, 48000);
      expect(report.bitDepth, 16);
      expect(report.channels, 1);
      expect(report.durationSeconds, closeTo(.6, .02));
      expect(report.clippedSamples, 0);
      expect(report.peakDbfs, lessThan(-10));
      expect(report.estimatedIntegratedLufs, greaterThan(-120));
      expect(report.estimatedMaxMomentaryLufs, greaterThan(-120));
      expect(report.sourceBytes, greaterThan(44));
      expect(report.sourceModifiedAtMs, greaterThan(0));
      expect(report.spectralBalance.length, 7);
      expect(report.platformChecks.any((e) => e.platform.contains('Spotify')),
          isTrue);
      expect(
        report.platformChecks
            .firstWhere((e) => e.platform.contains('Apple Digital Masters'))
            .ok,
        isFalse,
        reason: '16-bit synthetic source must not pass Apple 24-bit source check',
      );
    } finally {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}

List<int> _pcm16MonoSineWav({
  required int sampleRate,
  required double seconds,
  required double amplitude,
  required double frequency,
}) {
  final frames = (sampleRate * seconds).round();
  final dataBytes = frames * 2;
  final out = BytesBuilder(copy: false);

  void ascii(String value) => out.add(value.codeUnits);
  void u16(int value) {
    final d = ByteData(2)..setUint16(0, value, Endian.little);
    out.add(d.buffer.asUint8List());
  }

  void u32(int value) {
    final d = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(d.buffer.asUint8List());
  }

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(dataBytes);

  for (var i = 0; i < frames; i++) {
    final sample = (math.sin(2 * math.pi * frequency * i / sampleRate) *
            amplitude *
            32767)
        .round()
        .clamp(-32768, 32767);
    final d = ByteData(2)..setInt16(0, sample, Endian.little);
    out.add(d.buffer.asUint8List());
  }

  return out.takeBytes();
}
