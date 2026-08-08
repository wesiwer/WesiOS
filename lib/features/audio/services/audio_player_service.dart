import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/audio_vault_models.dart';

class AudioSpectrumFrame {
  final double bass;
  final double lowMid;
  final double mid;
  final double high;
  final double kick;
  final List<double> fft;
  final List<double> wave;

  const AudioSpectrumFrame({
    this.bass = 0,
    this.lowMid = 0,
    this.mid = 0,
    this.high = 0,
    this.kick = 0,
    this.fft = const [],
    this.wave = const [],
  });
}

class AudioPlayerState {
  final BeatEntry? beat;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final int queueIndex;
  final int queueLength;
  final String? error;

  const AudioPlayerState({
    this.beat,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 0.8,
    this.queueIndex = -1,
    this.queueLength = 0,
    this.error,
  });

  AudioPlayerState copyWith({
    BeatEntry? beat,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? volume,
    int? queueIndex,
    int? queueLength,
    String? error,
    bool clearError = false,
  }) =>
      AudioPlayerState(
        beat: beat ?? this.beat,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        queueIndex: queueIndex ?? this.queueIndex,
        queueLength: queueLength ?? this.queueLength,
        error: clearError ? null : (error ?? this.error),
      );
}

class AudioPlayerService {
  AudioPlayerService._();

  static final ValueNotifier<AudioPlayerState> state =
      ValueNotifier(const AudioPlayerState());
  static final ValueNotifier<AudioSpectrumFrame> spectrum =
      ValueNotifier(const AudioSpectrumFrame());

  static final SoLoud _soloud = SoLoud.instance;
  static AudioSource? _source;
  static SoundHandle? _handle;
  static AudioData? _audioData;
  static Timer? _ticker;
  static List<BeatEntry> _queue = const [];
  static int _index = -1;
  static double _lastBass = 0;
  static bool _initializing = false;

  static Future<void> initialize() async {
    if (_soloud.isInitialized || _initializing) return;
    _initializing = true;
    try {
      await _soloud.init(automaticCleanup: false);
      _soloud.setVisualizationEnabled(true);
      _audioData ??= AudioData(GetSamplesKind.linear);
      _ticker ??= Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    } finally {
      _initializing = false;
    }
  }

  static Future<void> setQueue(List<BeatEntry> beats, {String? startId}) async {
    _queue = beats.where((e) => e.playablePath != null).toList();
    _index = startId == null ? -1 : _queue.indexWhere((e) => e.id == startId);
    state.value = state.value.copyWith(
      queueLength: _queue.length,
      queueIndex: _index,
    );
  }

  static Future<void> playBeat(BeatEntry beat, {List<BeatEntry>? queue}) async {
    await initialize();
    if (queue != null) await setQueue(queue, startId: beat.id);
    if (_queue.isEmpty) {
      _queue = [beat];
      _index = 0;
    } else if (_index < 0 || _queue[_index].id != beat.id) {
      _index = _queue.indexWhere((e) => e.id == beat.id);
      if (_index < 0) {
        _queue = [..._queue, beat];
        _index = _queue.length - 1;
      }
    }
    final path = beat.playablePath;
    if (path == null) return;
    try {
      await _stopCurrent();
      _source = await _soloud.loadFile(path, mode: LoadMode.disk);
      final duration = _soloud.getLength(_source!);
      _handle = await _soloud.play(_source!, volume: state.value.volume);
      state.value = AudioPlayerState(
        beat: beat,
        playing: true,
        position: Duration.zero,
        duration: duration,
        volume: state.value.volume,
        queueIndex: _index,
        queueLength: _queue.length,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: 'Не удалось воспроизвести файл: $e');
    }
  }

  static Future<void> toggle() async {
    final handle = _handle;
    if (handle == null) return;
    try {
      final paused = _soloud.getPause(handle);
      _soloud.setPause(handle, !paused);
      state.value = state.value.copyWith(playing: paused, clearError: true);
    } catch (_) {}
  }

  static Future<void> seek(Duration position) async {
    final handle = _handle;
    if (handle == null) return;
    final safeMs = position.inMilliseconds
        .clamp(0, state.value.duration.inMilliseconds)
        .toInt();
    try {
      _soloud.seek(handle, Duration(milliseconds: safeMs));
      state.value = state.value.copyWith(position: Duration(milliseconds: safeMs));
    } catch (_) {}
  }

  static Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 1.0).toDouble();
    final handle = _handle;
    if (handle != null) {
      try {
        _soloud.setVolume(handle, v);
      } catch (_) {}
    }
    state.value = state.value.copyWith(volume: v);
  }

  static Future<void> next() async {
    if (_queue.isEmpty) return;
    final nextIndex = (_index + 1) % _queue.length;
    _index = nextIndex;
    await playBeat(_queue[nextIndex]);
  }

  static Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (state.value.position > const Duration(seconds: 4)) {
      await seek(Duration.zero);
      return;
    }
    _index = (_index - 1 + _queue.length) % _queue.length;
    await playBeat(_queue[_index]);
  }

  static Future<void> stop() async {
    await _stopCurrent();
    state.value = AudioPlayerState(volume: state.value.volume);
    spectrum.value = const AudioSpectrumFrame();
  }

  static Future<void> _stopCurrent() async {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      try {
        await _soloud.stop(handle);
      } catch (_) {}
    }
    final source = _source;
    _source = null;
    if (source != null) {
      try {
        await _soloud.disposeSource(source);
      } catch (_) {}
    }
  }

  static double _avg(Float32List values, int from, int to) {
    if (values.isEmpty) return 0;
    final a = from.clamp(0, values.length - 1).toInt();
    final b = to.clamp(a + 1, values.length).toInt();
    double sum = 0;
    for (var i = a; i < b; i++) {
      sum += values[i].abs();
    }
    return (sum / math.max(1, b - a)).clamp(0.0, 1.0).toDouble();
  }

  static void _tick() {
    final handle = _handle;
    if (handle == null || !_soloud.isInitialized) return;
    try {
      if (!_soloud.getIsValidVoiceHandle(handle)) {
        if (state.value.playing) {
          state.value = state.value.copyWith(
            playing: false,
            position: state.value.duration,
          );
          unawaited(next());
        }
        return;
      }
      final position = _soloud.getPosition(handle);
      final playing = !_soloud.getPause(handle);
      state.value = state.value.copyWith(position: position, playing: playing);

      final data = _audioData;
      if (data == null) return;
      data.updateSamples();
      final samples = data.getAudioData();
      if (samples.length < 512) return;
      final fftRaw = Float32List.fromList(samples.sublist(0, 256));
      final waveRaw = Float32List.fromList(samples.sublist(256, 512));
      final bass = (_avg(fftRaw, 1, 12) * 2.8).clamp(0.0, 1.0).toDouble();
      final lowMid = (_avg(fftRaw, 12, 42) * 2.4).clamp(0.0, 1.0).toDouble();
      final mid = (_avg(fftRaw, 42, 112) * 2.1).clamp(0.0, 1.0).toDouble();
      final high = (_avg(fftRaw, 112, 256) * 2.5).clamp(0.0, 1.0).toDouble();
      final kick = math.max(0.0, bass - _lastBass * 0.78).clamp(0.0, 1.0).toDouble();
      _lastBass = _lastBass * 0.72 + bass * 0.28;
      spectrum.value = AudioSpectrumFrame(
        bass: bass,
        lowMid: lowMid,
        mid: mid,
        high: high,
        kick: kick,
        fft: List<double>.from(fftRaw),
        wave: List<double>.from(waveRaw),
      );
    } catch (_) {}
  }
}
