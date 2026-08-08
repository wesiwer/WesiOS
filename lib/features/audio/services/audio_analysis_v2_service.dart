import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/audio_vault_extended_models.dart';
import 'audio_analysis_service.dart';

/// Расширенный локальный анализатор Wesi AI Audio.
///
/// Тяжёлая часть выполняется через [compute], поэтому чтение/разбор большого
/// WAV и спектральные расчёты не блокируют UI isolate.
class AudioAnalysisV2Service {
  AudioAnalysisV2Service._();

  static Future<AudioAnalysisReport> analyzeWav(String path) async {
    final json = await compute(_analyzeWavV2Isolate, path);
    return AudioAnalysisReport.fromJson(json);
  }
}

Future<Map<String, dynamic>> _analyzeWavV2Isolate(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const AudioAnalysisException('WAV-файл не найден.');
  }

  final stat = await file.stat();
  final raf = await file.open();
  try {
    final header = await _readHeader(raf);
    if (header.audioFormat != 1 && header.audioFormat != 3) {
      throw AudioAnalysisException(
        'Поддерживается PCM/IEEE Float WAV. Формат ${header.audioFormat} пока не поддерживается.',
      );
    }
    if (![16, 24, 32].contains(header.bitsPerSample)) {
      throw AudioAnalysisException(
        'Поддерживается WAV 16/24/32 bit. Сейчас: ${header.bitsPerSample} bit.',
      );
    }
    if (header.audioFormat == 3 && header.bitsPerSample != 32) {
      throw const AudioAnalysisException(
        'IEEE Float WAV сейчас поддерживается в 32-bit формате.',
      );
    }
    if (header.channels < 1 || header.channels > 2) {
      throw const AudioAnalysisException(
        'Quick Analysis рассчитан на mono/stereo master.',
      );
    }
    if (header.sampleRate <= 0) {
      throw const AudioAnalysisException('Некорректная частота дискретизации WAV.');
    }

    final bytesPerSample = header.bitsPerSample ~/ 8;
    final frameBytes = bytesPerSample * header.channels;
    final totalFrames = header.dataSize ~/ frameBytes;
    if (totalFrames <= 0) {
      throw const AudioAnalysisException('В WAV нет аудиоданных.');
    }

    await raf.setPosition(header.dataOffset);
    const framesPerChunk = 8192;

    double peak = 0;
    double truePeak = 0;
    double sumSq = 0;
    double sum = 0;
    double sumL2 = 0;
    double sumR2 = 0;
    double sumLR = 0;
    double midPower = 0;
    double sidePower = 0;
    int sampleCount = 0;
    int clipped = 0;
    int firstAudibleFrame = -1;
    int lastAudibleFrame = -1;
    int frameIndex = 0;

    final interpolationHistory =
        List.generate(header.channels, (_) => <double>[]);

    // 100 ms power buckets: из них быстро строятся 400 ms Momentary,
    // 3 s Short-term и приблизительный LRA без хранения всего PCM в памяти.
    final powerBlockFrames = math.max(1, header.sampleRate ~/ 10).toInt();
    final powerBlocks = <double>[];
    double blockPower = 0;
    int blockFrames = 0;

    while (frameIndex < totalFrames) {
      final frames = math.min(framesPerChunk, totalFrames - frameIndex).toInt();
      final chunk = await raf.read(frames * frameBytes);
      if (chunk.isEmpty) break;
      final data = ByteData.sublistView(Uint8List.fromList(chunk));
      final actualFrames = chunk.length ~/ frameBytes;

      for (var f = 0; f < actualFrames; f++) {
        final channelValues = List<double>.filled(header.channels, 0);
        bool audible = false;
        double frameSq = 0;

        for (var ch = 0; ch < header.channels; ch++) {
          final offset = f * frameBytes + ch * bytesPerSample;
          final value = _sample(
            data,
            offset,
            header.bitsPerSample,
            header.audioFormat,
          );
          channelValues[ch] = value;

          final av = value.abs();
          if (av > peak) peak = av;
          if (av >= .9999) clipped++;
          if (av >= .001) audible = true;

          final sq = value * value;
          frameSq += sq;
          sumSq += sq;
          sum += value;
          sampleCount++;

          final history = interpolationHistory[ch];
          history.add(value);
          if (history.length >= 4) {
            final p0 = history[history.length - 4];
            final p1 = history[history.length - 3];
            final p2 = history[history.length - 2];
            final p3 = history[history.length - 1];
            for (final t in const <double>[.25, .5, .75]) {
              final interpolated = _catmullRom(p0, p1, p2, p3, t).abs();
              if (interpolated > truePeak) truePeak = interpolated;
            }
            if (history.length > 4) history.removeAt(0);
          }
        }

        if (audible) {
          final absoluteFrame = frameIndex + f;
          if (firstAudibleFrame < 0) firstAudibleFrame = absoluteFrame;
          lastAudibleFrame = absoluteFrame;
        }

        if (header.channels == 2) {
          final l = channelValues[0];
          final r = channelValues[1];
          sumL2 += l * l;
          sumR2 += r * r;
          sumLR += l * r;
          final mid = (l + r) * .5;
          final side = (l - r) * .5;
          midPower += mid * mid;
          sidePower += side * side;
        }

        blockPower += frameSq / header.channels;
        blockFrames++;
        if (blockFrames >= powerBlockFrames) {
          powerBlocks.add(blockPower / blockFrames);
          blockPower = 0;
          blockFrames = 0;
        }
      }
      frameIndex += actualFrames;
    }

    if (blockFrames > 0) {
      powerBlocks.add(blockPower / blockFrames);
    }

    truePeak = math.max(truePeak, peak).toDouble();
    final meanSq = sumSq / math.max(1, sampleCount);
    final rms = math.sqrt(meanSq);
    final rmsDb = _db(rms);
    final estimatedLufs = _lufsFromPower(meanSq);
    final peakDb = _db(peak);
    final truePeakDb = _db(truePeak);
    final crest = peakDb - rmsDb;
    final plr = truePeakDb - estimatedLufs;

    final correlation = header.channels == 2
        ? (sumLR / math.sqrt(math.max(1e-18, sumL2 * sumR2)))
            .clamp(-1.0, 1.0)
            .toDouble()
        : 1.0;
    final dc = sampleCount == 0 ? 0.0 : sum / sampleCount;

    final channelBalanceDb = header.channels == 2
        ? _ratioDb(sumL2, sumR2).clamp(-60.0, 60.0).toDouble()
        : 0.0;
    final midSideRatioDb = header.channels == 2
        ? _ratioDb(sidePower, midPower).clamp(-120.0, 120.0).toDouble()
        : -120.0;

    final duration = totalFrames / header.sampleRate;
    final headSilence = firstAudibleFrame < 0
        ? duration
        : firstAudibleFrame / header.sampleRate;
    final tailSilence = lastAudibleFrame < 0
        ? duration
        : math.max(0, totalFrames - 1 - lastAudibleFrame) /
            header.sampleRate;
    final edgeSilencePercent = duration <= 0
        ? 0.0
        : (((headSilence + tailSilence) / duration) * 100)
            .clamp(0.0, 100.0)
            .toDouble();

    final momentary = _rollingLufs(powerBlocks, 4);
    final shortTerm = _rollingLufs(powerBlocks, 30);
    final maxMomentary = momentary.isEmpty
        ? estimatedLufs
        : momentary.reduce(math.max);
    final maxShortTerm = shortTerm.isEmpty
        ? estimatedLufs
        : shortTerm.reduce(math.max);
    final estimatedLra = _estimatedLra(shortTerm, estimatedLufs);

    final clippedPerMillion = sampleCount <= 0
        ? 0.0
        : clipped / sampleCount * 1000000.0;

    final spectrum = await _spectralBalance(raf, header, totalFrames);
    final insights = _insights(
      sampleRate: header.sampleRate,
      bitDepth: header.bitsPerSample,
      peakDb: peakDb,
      truePeakDb: truePeakDb,
      lufs: estimatedLufs,
      crest: crest,
      plr: plr,
      estimatedLra: estimatedLra,
      maxMomentary: maxMomentary,
      maxShortTerm: maxShortTerm,
      correlation: correlation,
      channelBalanceDb: channelBalanceDb,
      midSideRatioDb: midSideRatioDb,
      dc: dc,
      clipped: clipped,
      clippedPerMillion: clippedPerMillion,
      headSilence: headSilence,
      tailSilence: tailSilence,
      spectrum: spectrum,
    );

    final platformChecks = _platformChecks(
      lufs: estimatedLufs,
      truePeak: truePeakDb,
      clipped: clipped,
      sampleRate: header.sampleRate,
      bitDepth: header.bitsPerSample,
      channels: header.channels,
    );

    final report = AudioAnalysisReport(
      analyzedAt: DateTime.now(),
      sourcePath: path,
      sourceBytes: stat.size,
      sourceModifiedAtMs: stat.modified.millisecondsSinceEpoch,
      format: header.audioFormat == 3 ? 'WAV Float' : 'WAV PCM',
      sampleRate: header.sampleRate,
      bitDepth: header.bitsPerSample,
      channels: header.channels,
      durationSeconds: duration,
      peakDbfs: peakDb,
      estimatedTruePeakDbtp: truePeakDb,
      rmsDbfs: rmsDb,
      estimatedIntegratedLufs: estimatedLufs,
      crestFactorDb: crest,
      peakToLoudnessRatioDb: plr,
      estimatedLoudnessRangeLu: estimatedLra,
      estimatedMaxMomentaryLufs: maxMomentary,
      estimatedMaxShortTermLufs: maxShortTerm,
      stereoCorrelation: correlation,
      channelBalanceDb: channelBalanceDb,
      midSideRatioDb: midSideRatioDb,
      dcOffset: dc,
      clippedSamples: clipped,
      clippedSamplesPerMillion: clippedPerMillion,
      headSilenceSeconds: headSilence,
      tailSilenceSeconds: tailSilence,
      edgeSilencePercent: edgeSilencePercent,
      spectralBalance: spectrum,
      insights: insights,
      platformChecks: platformChecks,
      score: _score(insights),
      disclaimer:
          'Quick Analysis v2 — полностью локальный технический QC. LUFS/LRA/Momentary/Short-term и True Peak помечены как оценки: быстрый анализ не заменяет сертифицированный BS.1770/EBU R128 meter, Apple AAC encode audition или финальный delivery QC.',
    );

    return report.toJson();
  } finally {
    await raf.close();
  }
}

Future<_WavHeaderV2> _readHeader(RandomAccessFile raf) async {
  await raf.setPosition(0);
  final riff = await raf.read(12);
  if (riff.length < 12 ||
      _ascii(riff, 0, 4) != 'RIFF' ||
      _ascii(riff, 8, 4) != 'WAVE') {
    throw const AudioAnalysisException('Файл не является RIFF/WAVE.');
  }

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  while (true) {
    final chunkHeader = await raf.read(8);
    if (chunkHeader.length < 8) break;
    final id = _ascii(chunkHeader, 0, 4);
    final size = ByteData.sublistView(Uint8List.fromList(chunkHeader))
        .getUint32(4, Endian.little);

    if (id == 'fmt ') {
      final fmt = await raf.read(size);
      if (fmt.length < 16) {
        throw const AudioAnalysisException('Повреждён fmt chunk WAV.');
      }
      final bd = ByteData.sublistView(Uint8List.fromList(fmt));
      audioFormat = bd.getUint16(0, Endian.little);
      channels = bd.getUint16(2, Endian.little);
      sampleRate = bd.getUint32(4, Endian.little);
      bitsPerSample = bd.getUint16(14, Endian.little);

      // WAVE_FORMAT_EXTENSIBLE — частый вариант экспорта из DAW.
      // SubFormat GUID начинается с обычного WAVE format tag.
      if (audioFormat == 0xFFFE && fmt.length >= 40) {
        final subFormatTag = bd.getUint16(24, Endian.little);
        if (subFormatTag == 1 || subFormatTag == 3) {
          audioFormat = subFormatTag;
        }
      }
      if (size.isOdd) {
        await raf.setPosition((await raf.position()) + 1);
      }
    } else if (id == 'data') {
      dataOffset = await raf.position();
      dataSize = size;
      break;
    } else {
      await raf.setPosition(
        (await raf.position()) + size + (size.isOdd ? 1 : 0),
      );
    }
  }

  if (audioFormat == null ||
      channels == null ||
      sampleRate == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataSize == null) {
    throw const AudioAnalysisException('Не удалось прочитать структуру WAV.');
  }

  return _WavHeaderV2(
    audioFormat: audioFormat,
    channels: channels,
    sampleRate: sampleRate,
    bitsPerSample: bitsPerSample,
    dataOffset: dataOffset,
    dataSize: dataSize,
  );
}

Future<Map<String, double>> _spectralBalance(
  RandomAccessFile raf,
  _WavHeaderV2 h,
  int totalFrames,
) async {
  const window = 2048;
  final bytesPerSample = h.bitsPerSample ~/ 8;
  final frameBytes = bytesPerSample * h.channels;
  final labels = <String, List<double>>{
    'Sub 20–60': [28, 36, 46, 58],
    'Bass 60–120': [68, 82, 100, 118],
    'Low-mid 120–500': [150, 220, 330, 460],
    'Mid 0.5–2k': [650, 900, 1300, 1800],
    'Presence 2–5k': [2300, 3000, 3900, 4800],
    'High 5–10k': [5600, 6800, 8200, 9600],
    'Air 10–20k': [11000, 13000, 15500, 18500],
  };
  final energy = {for (final k in labels.keys) k: 0.0};
  const windows = 12;

  for (var wi = 0; wi < windows; wi++) {
    final center = ((wi + .5) / windows * totalFrames).floor();
    final start = (center - window ~/ 2)
        .clamp(0, math.max(0, totalFrames - window))
        .toInt();
    await raf.setPosition(h.dataOffset + start * frameBytes);
    final raw = await raf.read(window * frameBytes);
    final frames = raw.length ~/ frameBytes;
    if (frames < 64) continue;

    final bd = ByteData.sublistView(Uint8List.fromList(raw));
    final mono = List<double>.filled(frames, 0);
    for (var i = 0; i < frames; i++) {
      double value = 0;
      for (var ch = 0; ch < h.channels; ch++) {
        value += _sample(
          bd,
          i * frameBytes + ch * bytesPerSample,
          h.bitsPerSample,
          h.audioFormat,
        );
      }
      mono[i] = value / h.channels;
    }

    for (final entry in labels.entries) {
      for (final freq in entry.value) {
        if (freq >= h.sampleRate / 2) continue;
        energy[entry.key] =
            energy[entry.key]! + _goertzel(mono, h.sampleRate, freq);
      }
    }
  }

  final total = energy.values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return {for (final k in energy.keys) k: 0};
  return {for (final e in energy.entries) e.key: e.value / total};
}

double _goertzel(List<double> samples, int sampleRate, double freq) {
  final omega = 2 * math.pi * freq / sampleRate;
  final coeff = 2 * math.cos(omega);
  double s0 = 0;
  double s1 = 0;
  double s2 = 0;

  for (var i = 0; i < samples.length; i++) {
    final hann = .5 -
        .5 * math.cos(2 * math.pi * i / math.max(1, samples.length - 1));
    s0 = samples[i] * hann + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return math.max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2).toDouble();
}

List<double> _rollingLufs(List<double> power, int window) {
  if (power.isEmpty) return const [];
  final actualWindow = math.min(window, power.length).toInt();
  if (actualWindow <= 0) return const [];

  final out = <double>[];
  double sum = 0;
  for (var i = 0; i < power.length; i++) {
    sum += power[i];
    if (i >= actualWindow) sum -= power[i - actualWindow];
    if (i >= actualWindow - 1) {
      out.add(_lufsFromPower(sum / actualWindow));
    }
  }
  return out;
}

double _estimatedLra(List<double> shortTerm, double integratedLufs) {
  if (shortTerm.length < 2) return 0;
  final gate = math.max(-70.0, integratedLufs - 20.0);
  final values = shortTerm.where((v) => v > gate && v.isFinite).toList()..sort();
  if (values.length < 2) return 0;
  final p10 = _percentile(values, .10);
  final p95 = _percentile(values, .95);
  return math.max(0, p95 - p10).toDouble();
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;
  final pos = (sorted.length - 1) * p;
  final lo = pos.floor();
  final hi = pos.ceil();
  if (lo == hi) return sorted[lo];
  final t = pos - lo;
  return sorted[lo] * (1 - t) + sorted[hi] * t;
}

List<AudioAiInsight> _insights({
  required int sampleRate,
  required int bitDepth,
  required double peakDb,
  required double truePeakDb,
  required double lufs,
  required double crest,
  required double plr,
  required double estimatedLra,
  required double maxMomentary,
  required double maxShortTerm,
  required double correlation,
  required double channelBalanceDb,
  required double midSideRatioDb,
  required double dc,
  required int clipped,
  required double clippedPerMillion,
  required double headSilence,
  required double tailSilence,
  required Map<String, double> spectrum,
}) {
  final out = <AudioAiInsight>[];

  if (clipped > 0) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.critical,
      title: 'Обнаружен digital clipping',
      detail:
          '$clipped сэмплов у цифрового потолка (${clippedPerMillion.toStringAsFixed(1)} на миллион).',
      action:
          'Снизь уровень перед limiter/clipper, проверь gain staging и повтори экспорт.',
    ));
  }

  if (truePeakDb > -1) {
    out.add(AudioAiInsight(
      severity: truePeakDb > -.2
          ? AudioIssueSeverity.critical
          : AudioIssueSeverity.warning,
      title: 'Мало true-peak headroom',
      detail: 'True Peak est.: ${truePeakDb.toStringAsFixed(2)} dBTP.',
      action:
          'Для streaming-safe экспорта опусти output ceiling; при громком Spotify-master ориентируйся на запас до -2 dBTP.',
    ));
  }

  if (lufs > -8) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Очень плотный master',
      detail:
          'Integrated loudness est. ${lufs.toStringAsFixed(1)} LUFS, PLR ${plr.toStringAsFixed(1)} dB.',
      action:
          'Сделай loudness-matched A/B с референсом и проверь, не съедены ли transient/punch limiter-ом.',
    ));
  } else if (lufs < -20) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Низкая средняя громкость',
      detail: 'Integrated loudness est. ${lufs.toStringAsFixed(1)} LUFS.',
      action:
          'Если это финальный master, проверь намеренность такого уровня и сравни с жанровым референсом после loudness matching.',
    ));
  }

  if (plr < 6) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Низкий PLR — возможный over-limiting',
      detail:
          'Peak-to-Loudness Ratio ${plr.toStringAsFixed(1)} dB. Это может означать слишком плотный limiter/clipper chain.',
      action:
          'Ослабь финальное ограничение на 1–2 dB и сравни punch, kick/snare transients и low-end.',
    ));
  }

  if (estimatedLra < 1.5 && lufs > -16) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Очень узкий loudness range',
      detail:
          'LRA est. ${estimatedLra.toStringAsFixed(1)} LU; Max Short-term ${maxShortTerm.toStringAsFixed(1)} LUFS.',
      action:
          'Это может быть нормально для плотного жанра, но проверь, осталась ли музыкальная макродинамика между секциями.',
    ));
  }

  final absBalance = channelBalanceDb.abs();
  if (absBalance > 1.5) {
    out.add(AudioAiInsight(
      severity: absBalance > 3
          ? AudioIssueSeverity.warning
          : AudioIssueSeverity.info,
      title: 'Неравномерный L/R баланс',
      detail:
          '${channelBalanceDb > 0 ? 'Левый' : 'Правый'} канал в среднем громче примерно на ${absBalance.toStringAsFixed(1)} dB.',
      action:
          'Проверь панораму, stereo bus processing и не является ли перекос частью аранжировки.',
    ));
  }

  if (correlation < 0) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.critical,
      title: 'Риск фазового развала в mono',
      detail:
          'Stereo correlation ${correlation.toStringAsFixed(2)}. Отрицательная корреляция означает существенную противофазу.',
      action:
          'Проверь stereo widening, Haas/delay, polarity и обязательно послушай master в mono.',
    ));
  } else if (correlation < .2) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Очень широкий stereo image',
      detail:
          'Stereo correlation ${correlation.toStringAsFixed(2)}, M/S ${midSideRatioDb.toStringAsFixed(1)} dB.',
      action:
          'Проверь mono compatibility и особенно низкие частоты после fold-down.',
    ));
  } else if (midSideRatioDb > -3) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Высокая Side-энергия',
      detail: 'M/S energy ratio ${midSideRatioDb.toStringAsFixed(1)} dB.',
      action:
          'Проверь, что ширина не держится только на phase tricks и не исчезает в mono.',
    ));
  }

  if (dc.abs() > .002) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Заметный DC offset',
      detail: 'Среднее смещение ${(dc * 100).toStringAsFixed(3)}%.',
      action:
          'Найди источник DC в chain или используй корректный DC removal/high-pass до финального limiter.',
    ));
  }

  if (sampleRate < 44100) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Низкий sample rate',
      detail: '$sampleRate Hz — ниже обычного музыкального delivery уровня 44.1 kHz.',
      action: 'Проверь настройки проекта и экспорта.',
    ));
  }

  if (bitDepth < 24) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: '16-bit master',
      detail:
          '$bitDepth bit подходит для ряда сценариев, но Apple Digital Masters source profile требует 24-bit source.',
      action:
          'Если целишься в Apple Digital Masters, экспортируй нативный 24-bit master без искусственного bit-padding.',
    ));
  }

  if (headSilence > 1.0) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Длинная тишина в начале',
      detail: '${headSilence.toStringAsFixed(2)} с до первого слышимого сигнала.',
      action: 'Проверь trim/start marker перед delivery.',
    ));
  }

  if (tailSilence > 4.0) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Длинный хвост тишины',
      detail: '${tailSilence.toStringAsFixed(2)} с после последнего слышимого сигнала.',
      action: 'Проверь fade/reverb tail и конечный trim.',
    ));
  }

  final sub = spectrum['Sub 20–60'] ?? 0;
  final lowMid = spectrum['Low-mid 120–500'] ?? 0;
  final presence = spectrum['Presence 2–5k'] ?? 0;
  final high = spectrum['High 5–10k'] ?? 0;
  if (sub > .24) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Много sub-энергии',
      detail: 'Sub занимает примерно ${(sub * 100).toStringAsFixed(0)}% выборочной спектральной энергии.',
      action:
          'Проверь rumble, kick/808 overlap и headroom ниже 60 Hz на нормальных мониторах/анализаторе.',
    ));
  }
  if (lowMid > .32) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Возможный low-mid mud',
      detail:
          '120–500 Hz занимают около ${(lowMid * 100).toStringAsFixed(0)}% выборочной спектральной энергии.',
      action:
          'Проверь masking между bass, body инструментов и ambience; не режь диапазон автоматически без прослушивания.',
    ));
  }
  if (presence + high > .42) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.warning,
      title: 'Яркая верхняя середина / high',
      detail:
          '2–10 kHz суммарно около ${((presence + high) * 100).toStringAsFixed(0)}% выборочной энергии.',
      action:
          'Проверь harshness на вокале, hats/snare и limiter distortion на тихой громкости.',
    ));
  }

  if (out.isEmpty) {
    out.add(const AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Критических технических проблем не найдено',
      detail:
          'Quick Analysis не увидел clipping, явных phase/DC проблем или экстремального tonal/dynamic перекоса.',
      action:
          'Сделай финальный A/B с референсом и проверь master на нескольких системах воспроизведения.',
    ));
  }

  // Максимальные окна выводятся в UI, здесь используем значения, чтобы
  // анализатор не терял контекст при экстремальных кратких всплесках.
  if (maxMomentary > -5 && truePeakDb > -1) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Очень громкие краткие участки',
      detail:
          'Max Momentary est. ${maxMomentary.toStringAsFixed(1)} LUFS при True Peak ${truePeakDb.toStringAsFixed(2)} dBTP.',
      action:
          'Проверь самые громкие 400 ms на distortion/pumping, а не только интегральную громкость.',
    ));
  }

  // Crest используется как независимая sanity-проверка PLR.
  if (crest < 4 && plr < 7) {
    out.add(AudioAiInsight(
      severity: AudioIssueSeverity.info,
      title: 'Низкий crest factor',
      detail: 'Crest ${crest.toStringAsFixed(1)} dB, PLR ${plr.toStringAsFixed(1)} dB.',
      action:
          'Проверь, не срезаны ли transient peaks до limiter-а clipper-ом или saturation chain.',
    ));
  }

  return out;
}

List<AudioPlatformCheck> _platformChecks({
  required double lufs,
  required double truePeak,
  required int clipped,
  required int sampleRate,
  required int bitDepth,
  required int channels,
}) {
  final spotifyLimit = lufs > -14 ? -2.0 : -1.0;
  final spotifyGain = -14 - lufs;
  final spotifySafe = truePeak <= spotifyLimit && clipped == 0;

  const appleRates = <int>{44100, 48000, 88200, 96000, 176400, 192000};
  final appleFileSideOk =
      bitDepth >= 24 && appleRates.contains(sampleRate) && clipped == 0;

  final ebuNearTarget = (lufs + 23).abs() <= .5;
  final ebuReferenceOk = ebuNearTarget && truePeak <= -1 && clipped == 0;

  final streamingSafe = truePeak <= -1 && clipped == 0;

  return [
    AudioPlatformCheck(
      platform: 'Spotify · Normal',
      ok: spotifySafe,
      targetLufs: -14,
      maxTruePeakDbtp: spotifyLimit,
      normalizationGainDb: spotifyGain,
      basis: 'Official guidance',
      sourceLabel: 'Spotify Loudness normalization',
      summary: spotifySafe
          ? 'Playback-safe по опубликованным mastering tips: loudness est. ${lufs.toStringAsFixed(1)} LUFS, ожидаемая нормализация ${spotifyGain >= 0 ? '+' : ''}${spotifyGain.toStringAsFixed(1)} dB, True Peak est. ${truePeak.toStringAsFixed(2)} dBTP.'
          : 'Нужна проверка headroom: Spotify указывает -14 LUFS как mastering target, максимум -1 dBTP; для masters громче -14 LUFS рекомендует держать True Peak ниже -2 dBTP.',
    ),
    AudioPlatformCheck(
      platform: 'Apple Digital Masters · source profile',
      ok: appleFileSideOk,
      basis: 'Official source profile',
      sourceLabel: 'Apple Video and Audio Asset Guide',
      summary: appleFileSideOk
          ? '${bitDepth}-bit / ${(sampleRate / 1000).toStringAsFixed(sampleRate % 1000 == 0 ? 0 : 1)} kHz проходит проверяемую часть source profile; clipping не найден. WesiOS не может доказать исходное разрешение проекта или заменить обязательное прослушивание Apple AAC encode.'
          : 'Для Apple Digital Masters source profile нужен минимум 24-bit и допустимый sample rate 44.1/48/88.2/96/176.4/192 kHz; также нельзя полагаться на файл с audible clipping. Текущий файл: $bitDepth-bit, $sampleRate Hz.',
    ),
    AudioPlatformCheck(
      platform: 'EBU R128 · broadcast reference',
      ok: ebuReferenceOk,
      targetLufs: -23,
      maxTruePeakDbtp: -1,
      normalizationGainDb: -23 - lufs,
      basis: 'Broadcast reference',
      sourceLabel: 'EBU R 128 v5 / EBU Tech 3341',
      summary: ebuReferenceOk
          ? 'Оценка находится рядом с broadcast reference -23 LUFS и ниже -1 dBTP. Это не является сертифицированным R128 compliance test, потому что Quick Analysis использует быстрые оценки.'
          : 'Broadcast reference EBU R128: -23 LUFS (для обычной программы допуск ±0.5 LU); True Peak descriptor также контролируется. Quick Analysis показывает ${lufs.toStringAsFixed(1)} LUFS est. / ${truePeak.toStringAsFixed(2)} dBTP est.',
    ),
    AudioPlatformCheck(
      platform: 'YouTube · technical playback QC',
      ok: streamingSafe,
      maxTruePeakDbtp: -1,
      basis: 'Wesi QC · not an official LUFS target',
      sourceLabel: 'YouTube Help documents automatic audio/Stable volume processing',
      summary: streamingSafe
          ? 'Клиппинга нет и есть минимум ~1 dB true-peak headroom по внутреннему Wesi streaming-safe QC. WesiOS намеренно не показывает фиксированный «YouTube LUFS standard»: в используемой официальной справке такого upload mastering target не заявлено.'
          : 'Для безопасного транскодирования WesiOS рекомендует убрать clipping и оставить около 1 dB true-peak headroom. Это внутренний QC, а не официальный YouTube mastering target.',
    ),
    AudioPlatformCheck(
      platform: 'Wesi Streaming Safe',
      ok: streamingSafe && channels <= 2,
      maxTruePeakDbtp: -1,
      basis: 'Wesi QC',
      sourceLabel: 'Internal cross-platform technical check',
      summary: streamingSafe
          ? 'Нет digital clipping, True Peak est. ≤ -1 dBTP, mono/stereo delivery.'
          : 'Убери clipping и/или оставь больше true-peak headroom перед lossy transcoding.',
    ),
  ];
}

int _score(List<AudioAiInsight> insights) {
  int score = 100;
  for (final issue in insights) {
    score -= switch (issue.severity) {
      AudioIssueSeverity.critical => 18,
      AudioIssueSeverity.warning => 8,
      AudioIssueSeverity.info => 2,
    };
  }
  return score.clamp(0, 100);
}

double _sample(
  ByteData data,
  int offset,
  int bitsPerSample,
  int audioFormat,
) {
  if (audioFormat == 3 && bitsPerSample == 32) {
    final value = data.getFloat32(offset, Endian.little);
    return value.isFinite ? value : 0;
  }

  switch (bitsPerSample) {
    case 16:
      return data.getInt16(offset, Endian.little) / 32768.0;
    case 24:
      var value = data.getUint8(offset) |
          (data.getUint8(offset + 1) << 8) |
          (data.getUint8(offset + 2) << 16);
      if ((value & 0x800000) != 0) value |= ~0xFFFFFF;
      return value / 8388608.0;
    case 32:
      return data.getInt32(offset, Endian.little) / 2147483648.0;
    default:
      return 0;
  }
}

double _catmullRom(double p0, double p1, double p2, double p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  return .5 *
      ((2 * p1) +
          (-p0 + p2) * t +
          (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
          (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
}

double _lufsFromPower(double power) {
  if (power <= 0 || !power.isFinite) return -120;
  return -0.691 + 10 * _log10(power);
}

double _db(double amplitude) {
  if (amplitude <= 0 || !amplitude.isFinite) return -120;
  return 20 * _log10(amplitude);
}

double _ratioDb(double numerator, double denominator) {
  if (numerator <= 0 && denominator <= 0) return 0;
  if (numerator <= 0) return -120;
  if (denominator <= 0) return 120;
  return 10 * _log10(numerator / denominator);
}

double _log10(double value) => math.log(value) / math.ln10;

String _ascii(List<int> bytes, int start, int length) =>
    String.fromCharCodes(bytes.skip(start).take(length));

class _WavHeaderV2 {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;

  const _WavHeaderV2({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
