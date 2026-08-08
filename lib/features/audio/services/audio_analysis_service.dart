import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/audio_vault_extended_models.dart';

class AudioAnalysisException implements Exception {
  final String message;
  const AudioAnalysisException(this.message);
  @override
  String toString() => message;
}

class AudioAnalysisService {
  AudioAnalysisService._();

  static Future<AudioAnalysisReport> analyzeWav(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const AudioAnalysisException('WAV-файл не найден.');
    }
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
      if (header.channels < 1 || header.channels > 2) {
        throw const AudioAnalysisException(
          'Быстрый анализ рассчитан на mono/stereo master.',
        );
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
      int sampleCount = 0;
      int clipped = 0;
      int firstAudibleFrame = -1;
      int lastAudibleFrame = -1;
      var frameIndex = 0;
      final history = List.generate(header.channels, (_) => <double>[]);

      while (frameIndex < totalFrames) {
        final frames = math.min(framesPerChunk, totalFrames - frameIndex);
        final chunk = await raf.read(frames * frameBytes);
        if (chunk.isEmpty) break;
        final data = ByteData.sublistView(Uint8List.fromList(chunk));
        final actualFrames = chunk.length ~/ frameBytes;
        for (var f = 0; f < actualFrames; f++) {
          final channelValues = <double>[];
          var audible = false;
          for (var ch = 0; ch < header.channels; ch++) {
            final offset = f * frameBytes + ch * bytesPerSample;
            final value = _sample(
              data,
              offset,
              header.bitsPerSample,
              header.audioFormat,
            );
            channelValues.add(value);
            final av = value.abs();
            if (av > peak) peak = av;
            if (av >= .9999) clipped++;
            if (av >= .001) audible = true;
            sumSq += value * value;
            sum += value;
            sampleCount++;

            final h = history[ch];
            h.add(value);
            if (h.length >= 4) {
              final p0 = h[h.length - 4];
              final p1 = h[h.length - 3];
              final p2 = h[h.length - 2];
              final p3 = h[h.length - 1];
              for (final t in const [.25, .5, .75]) {
                final interpolated = _catmullRom(p0, p1, p2, p3, t).abs();
                if (interpolated > truePeak) truePeak = interpolated;
              }
              if (h.length > 4) h.removeAt(0);
            }
          }
          if (audible) {
            firstAudibleFrame =
                firstAudibleFrame < 0 ? frameIndex + f : firstAudibleFrame;
            lastAudibleFrame = frameIndex + f;
          }
          if (header.channels == 2) {
            final l = channelValues[0];
            final r = channelValues[1];
            sumL2 += l * l;
            sumR2 += r * r;
            sumLR += l * r;
          }
        }
        frameIndex += actualFrames;
      }

      truePeak = math.max(truePeak, peak);
      final meanSq = sumSq / math.max(1, sampleCount);
      final rms = math.sqrt(meanSq);
      final rmsDb = _db(rms);
      final estimatedLufs =
          meanSq <= 0 ? -120.0 : -0.691 + 10 * _log10(meanSq);
      final peakDb = _db(peak);
      final truePeakDb = _db(truePeak);
      final crest = peakDb - rmsDb;
      final correlation = header.channels == 2
          ? (sumLR / math.sqrt(math.max(1e-18, sumL2 * sumR2)))
              .clamp(-1.0, 1.0)
              .toDouble()
          : 1.0;
      final dc = sampleCount == 0 ? 0.0 : sum / sampleCount;
      final duration = totalFrames / header.sampleRate;
      final headSilence = firstAudibleFrame < 0
          ? duration
          : firstAudibleFrame / header.sampleRate;
      final tailSilence = lastAudibleFrame < 0
          ? duration
          : math.max(0, totalFrames - 1 - lastAudibleFrame) /
              header.sampleRate;

      final spectrum = await _spectralBalance(raf, header, totalFrames);
      final insights = _insights(
        sampleRate: header.sampleRate,
        bitDepth: header.bitsPerSample,
        peakDb: peakDb,
        truePeakDb: truePeakDb,
        lufs: estimatedLufs,
        crest: crest,
        correlation: correlation,
        dc: dc,
        clipped: clipped,
        headSilence: headSilence,
        tailSilence: tailSilence,
        spectrum: spectrum,
      );
      final platformChecks =
          _platformChecks(estimatedLufs, truePeakDb, clipped);
      final score = _score(insights);

      return AudioAnalysisReport(
        analyzedAt: DateTime.now(),
        sourcePath: path,
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
        stereoCorrelation: correlation,
        dcOffset: dc,
        clippedSamples: clipped,
        headSilenceSeconds: headSilence,
        tailSilenceSeconds: tailSilence,
        spectralBalance: spectrum,
        insights: insights,
        platformChecks: platformChecks,
        score: score,
        disclaimer:
            'Quick Analysis — локальный технический анализ. LUFS/True Peak являются быстрыми оценками и не заменяют сертифицированный BS.1770/R128 meter для финального delivery QC.',
      );
    } finally {
      await raf.close();
    }
  }

  static Future<_WavHeader> _readHeader(RandomAccessFile raf) async {
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
    return _WavHeader(
      audioFormat: audioFormat,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }

  static Future<Map<String, double>> _spectralBalance(
    RandomAccessFile raf,
    _WavHeader h,
    int totalFrames,
  ) async {
    const window = 2048;
    final bytesPerSample = h.bitsPerSample ~/ 8;
    final frameBytes = bytesPerSample * h.channels;
    final labels = <String, List<double>>{
      'Sub 20–60': [32, 45, 58],
      'Bass 60–120': [70, 90, 115],
      'Low-mid 120–500': [150, 260, 420],
      'Mid 0.5–2k': [650, 1000, 1700],
      'Presence 2–5k': [2400, 3400, 4700],
      'High 5–10k': [5600, 7400, 9200],
      'Air 10–20k': [11000, 14000, 18000],
    };
    final energy = {for (final k in labels.keys) k: 0.0};
    const windows = 9;
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
        double v = 0;
        for (var ch = 0; ch < h.channels; ch++) {
          v += _sample(
            bd,
            i * frameBytes + ch * bytesPerSample,
            h.bitsPerSample,
            h.audioFormat,
          );
        }
        mono[i] = v / h.channels;
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

  static double _goertzel(
      List<double> samples, int sampleRate, double freq) {
    final omega = 2 * math.pi * freq / sampleRate;
    final coeff = 2 * math.cos(omega);
    double s0 = 0, s1 = 0, s2 = 0;
    for (var i = 0; i < samples.length; i++) {
      final hann = .5 -
          .5 *
              math.cos(
                2 * math.pi * i / math.max(1, samples.length - 1),
              );
      s0 = samples[i] * hann + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return math.max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2);
  }

  static List<AudioAiInsight> _insights({
    required int sampleRate,
    required int bitDepth,
    required double peakDb,
    required double truePeakDb,
    required double lufs,
    required double crest,
    required double correlation,
    required double dc,
    required int clipped,
    required double headSilence,
    required double tailSilence,
    required Map<String, double> spectrum,
  }) {
    final out = <AudioAiInsight>[];
    if (clipped > 0) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.critical,
        title: 'Обнаружен clipping',
        detail: '$clipped сэмплов достигли цифрового потолка.',
        action:
            'Снизь уровень перед лимитером/клиппером и проверь gain staging.',
      ));
    }
    if (truePeakDb > -1) {
      out.add(AudioAiInsight(
        severity: truePeakDb > -.2
            ? AudioIssueSeverity.critical
            : AudioIssueSeverity.warning,
        title: 'Мало true-peak headroom',
        detail: 'Оценка True Peak: ${truePeakDb.toStringAsFixed(2)} dBTP.',
        action:
            'Для streaming-safe master опусти ceiling примерно до -1 dBTP; для очень громкого master Spotify рекомендует ниже -2 dBTP.',
      ));
    }
    if (lufs > -8) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Очень плотный master',
        detail:
            'Оценка loudness ${lufs.toStringAsFixed(1)} LUFS — высок риск потери punch и транзиентов.',
        action:
            'Сравни с референсом после loudness matching; попробуй меньше limiter gain reduction.',
      ));
    } else if (lufs < -19) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.info,
        title: 'Низкая средняя громкость',
        detail: 'Оценка loudness ${lufs.toStringAsFixed(1)} LUFS.',
        action:
            'Если это финальный master, проверь, намеренно ли оставлен такой запас.',
      ));
    }
    if (crest < 4.5) {
      out.add(const AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Низкий crest factor',
        detail:
            'Пики почти не отделяются от среднего уровня — возможен over-limiting.',
        action: 'Проверь kick/snare transients и release лимитера.',
      ));
    }
    if (correlation < 0) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.critical,
        title: 'Риск фазовой отмены в mono',
        detail: 'Stereo correlation ${correlation.toStringAsFixed(2)}.',
        action: 'Проверь widening, Haas/delay и низ в mono.',
      ));
    } else if (correlation < .25) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Очень широкая стереобаза',
        detail:
            'Stereo correlation ${correlation.toStringAsFixed(2)} — mono compatibility стоит проверить вручную.',
        action: 'Сузь sub/bass и проверь side-компонент.',
      ));
    }
    if (dc.abs() > .005) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'DC offset',
        detail: 'Среднее смещение ${(dc * 100).toStringAsFixed(2)}%.',
        action: 'Проверь DC filter/high-pass на master chain.',
      ));
    }
    if (headSilence > .25) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.info,
        title: 'Длинная тишина в начале',
        detail: '${headSilence.toStringAsFixed(2)} сек до первого сигнала.',
        action: 'Для релиза обычно стоит обрезать лишний pre-roll.',
      ));
    }
    if (tailSilence > 2) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.info,
        title: 'Длинный хвост тишины',
        detail:
            '${tailSilence.toStringAsFixed(1)} сек после последнего сигнала.',
        action: 'Проверь fade/reverb tail и экспортный диапазон.',
      ));
    }
    final sub = spectrum['Sub 20–60'] ?? 0;
    final lowMid = spectrum['Low-mid 120–500'] ?? 0;
    final presence = spectrum['Presence 2–5k'] ?? 0;
    final high =
        (spectrum['High 5–10k'] ?? 0) + (spectrum['Air 10–20k'] ?? 0);
    if (sub > .24) {
      out.add(const AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Саб доминирует',
        detail:
            'В выбранных спектральных окнах слишком большая доля энергии ниже 60 Hz.',
        action:
            'Проверь 808/kick конфликт, rumble и переводимость на маленькие системы.',
      ));
    }
    if (lowMid > .34) {
      out.add(const AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Возможная мутность low-mid',
        detail: 'Диапазон 120–500 Hz заметно доминирует.',
        action:
            'Проверь masking баса, пэдов, пиано и тела snare на референсе.',
      ));
    }
    if (presence > .30 || high > .38) {
      out.add(const AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Риск резкости/усталости',
        detail:
            'Верхняя середина/верх выражены сильнее типичного сбалансированного профиля.',
        action:
            'Проверь hats, distortion и 2–10 kHz на тихой громкости.',
      ));
    }
    if (sampleRate < 44100 || bitDepth < 16) {
      out.add(AudioAiInsight(
        severity: AudioIssueSeverity.warning,
        title: 'Низкие параметры master-файла',
        detail: '$sampleRate Hz / $bitDepth bit.',
        action:
            'Для архива храни lossless master минимум 44.1 kHz / 16 bit, лучше исходную render-разрядность.',
      ));
    }
    if (out.isEmpty) {
      out.add(const AudioAiInsight(
        severity: AudioIssueSeverity.info,
        title: 'Критичных технических проблем не найдено',
        detail:
            'Быстрые проверки уровня, клиппинга, стерео и спектра прошли без явных красных флагов.',
        action:
            'Сделай финальную проверку на референсах и нескольких системах воспроизведения.',
      ));
    }
    return out;
  }

  static List<AudioPlatformCheck> _platformChecks(
      double lufs, double truePeak, int clipped) {
    final spotifyLimit = lufs > -14 ? -2.0 : -1.0;
    final spotifyGain = -14 - lufs;
    return [
      AudioPlatformCheck(
        platform: 'Spotify Normal',
        ok: truePeak <= spotifyLimit && clipped == 0,
        targetLufs: -14,
        maxTruePeakDbtp: spotifyLimit,
        normalizationGainDb: spotifyGain,
        summary: truePeak <= spotifyLimit && clipped == 0
            ? 'True Peak в безопасной зоне; ожидаемая нормализация ${spotifyGain >= 0 ? '+' : ''}${spotifyGain.toStringAsFixed(1)} dB.'
            : 'Возможен риск transcoding distortion: Spotify для этого уровня громкости рекомендует True Peak ≤ ${spotifyLimit.toStringAsFixed(0)} dBTP.',
      ),
      AudioPlatformCheck(
        platform: 'Wesi Streaming Safe',
        ok: truePeak <= -1 && clipped == 0,
        maxTruePeakDbtp: -1,
        summary: truePeak <= -1 && clipped == 0
            ? 'Есть минимум 1 dB true-peak headroom и нет цифрового clipping.'
            : 'Для универсального streaming-safe master оставь ≥1 dB true-peak headroom и убери clipping.',
      ),
      AudioPlatformCheck(
        platform: 'EBU R128 reference',
        ok: (lufs + 23).abs() <= 1 && truePeak <= -1,
        targetLufs: -23,
        maxTruePeakDbtp: -1,
        normalizationGainDb: -23 - lufs,
        summary:
            'Broadcast reference; музыкальный streaming-master не обязан соответствовать -23 LUFS.',
      ),
    ];
  }

  static int _score(List<AudioAiInsight> insights) {
    var score = 100;
    for (final i in insights) {
      score -= switch (i.severity) {
        AudioIssueSeverity.critical => 18,
        AudioIssueSeverity.warning => 7,
        AudioIssueSeverity.info => 0,
      };
    }
    return score.clamp(0, 100).toInt();
  }

  static double _sample(ByteData d, int offset, int bits, int format) {
    if (format == 3 && bits == 32) {
      return d
          .getFloat32(offset, Endian.little)
          .clamp(-1.5, 1.5)
          .toDouble();
    }
    switch (bits) {
      case 16:
        return d.getInt16(offset, Endian.little) / 32768.0;
      case 24:
        var value = d.getUint8(offset) |
            (d.getUint8(offset + 1) << 8) |
            (d.getUint8(offset + 2) << 16);
        if ((value & 0x800000) != 0) value |= ~0xffffff;
        return value / 8388608.0;
      case 32:
        return d.getInt32(offset, Endian.little) / 2147483648.0;
      default:
        return 0;
    }
  }

  static double _catmullRom(
      double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return .5 *
        ((2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  }

  static double _db(double v) => v <= 1e-12 ? -120 : 20 * _log10(v);
  static double _log10(double v) => math.log(v) / math.ln10;
  static String _ascii(List<int> b, int start, int length) =>
      String.fromCharCodes(b.skip(start).take(length));
}

class _WavHeader {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;

  const _WavHeader({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
