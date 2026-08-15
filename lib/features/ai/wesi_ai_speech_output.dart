import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/sync/sync_endpoint.dart';
import 'models/wesi_ai_chat_models.dart';

/// Speech output for assistant replies.
///
/// When the authenticated Wesi AI Relay is available, Zane/Nirvana replies
/// use natural server-side TTS. If Relay/provider access is not configured or
/// temporarily fails, the conversation falls back to the platform voice and
/// continues instead of becoming silent.
///
/// No provider credential is ever present in the Flutter client.
class WesiAiSpeechOutput {
  static const MethodChannel _androidChannel = MethodChannel('wesios/ai_speech');
  static final AudioPlayer _naturalPlayer = AudioPlayer();
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  static Process? _windowsProcess;
  static Completer<void>? _naturalDone;
  static int _naturalGeneration = 0;

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isWindows;
  }

  static Future<bool> isAvailable() async {
    if (!isSupported) return false;
    if (Platform.isAndroid) {
      try {
        return await _androidChannel.invokeMethod<bool>('isAvailable') ?? false;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) return true;
    return false;
  }

  static Future<bool> speak(
    String text, {
    WesiAiMessageAuthor? author,
    String languageTag = 'ru-RU',
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || !isSupported) return false;
    await stop();

    if (author == WesiAiMessageAuthor.zane ||
        author == WesiAiMessageAuthor.nirvana) {
      final natural = await _speakNatural(clean, author!);
      if (natural) return true;
    }

    return _speakLocal(clean, author: author, languageTag: languageTag);
  }

  /// Requests natural speech from Main Server -> Foreign Relay -> provider.
  /// Returns only after playback is actually complete or interrupted, because
  /// the hands-free session must not reopen the microphone while the speaker
  /// is still producing the assistant's voice.
  static Future<bool> _speakNatural(
    String text,
    WesiAiMessageAuthor author,
  ) async {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = SyncEndpoint.sessionId;
    if (!SyncEndpoint.isConnected ||
        token is! String ||
        token.isEmpty ||
        sessionId == null) {
      return false;
    }

    try {
      final base = Uri.parse(SyncEndpoint.url);
      final uri = base.replace(path: '/api/wesi/ai/tts');
      final request = await _http.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, dynamic>{
        'persona': author == WesiAiMessageAuthor.nirvana ? 'nirvana' : 'zane',
        'text': text.length <= 8000 ? text : text.substring(0, 8000),
      }));
      final response = await request.close().timeout(const Duration(seconds: 125));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300 || raw.isEmpty) {
        return false;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final map = Map<String, dynamic>.from(decoded);
      if (map['ok'] != true) return false;
      final encoded = '${map['audioBase64'] ?? ''}';
      if (encoded.isEmpty || encoded.length > 28 * 1024 * 1024) return false;
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) return false;
      return await _playNatural(Uint8List.fromList(bytes));
    } on SocketException {
      return false;
    } on HttpException {
      return false;
    } on TimeoutException {
      return false;
    } on FormatException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _playNatural(Uint8List bytes) async {
    final generation = ++_naturalGeneration;
    final done = Completer<void>();
    _naturalDone = done;
    late final StreamSubscription<void> subscription;
    subscription = _naturalPlayer.onPlayerComplete.listen((_) {
      if (generation == _naturalGeneration && !done.isCompleted) {
        done.complete();
      }
    });

    try {
      await _naturalPlayer.play(BytesSource(bytes));
      await done.future.timeout(
        const Duration(minutes: 6),
        onTimeout: () async {
          if (generation == _naturalGeneration) {
            await _naturalPlayer.stop();
          }
        },
      );
      return generation == _naturalGeneration;
    } catch (_) {
      return false;
    } finally {
      await subscription.cancel();
      if (identical(_naturalDone, done)) _naturalDone = null;
    }
  }

  static Future<bool> _speakLocal(
    String clean, {
    required WesiAiMessageAuthor? author,
    required String languageTag,
  }) async {
    final profile = _profile(author);
    if (Platform.isAndroid) {
      try {
        return await _androidChannel.invokeMethod<bool>('speak', <String, dynamic>{
              'text': clean,
              'languageTag': languageTag,
              'rate': profile.rate,
              'pitch': profile.pitch,
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isWindows) {
      final bounded = clean.length <= 12000 ? clean : clean.substring(0, 12000);
      final encoded = base64Encode(utf8.encode(bounded));
      // The only variable embedded in the script is base64, which contains no
      // PowerShell command separators or quotes from the assistant response.
      final psRate = ((profile.rate - 1.0) * 5).round().clamp(-3, 3);
      final script = <String>[
        r'$ErrorActionPreference = "Stop"'.replaceAll(r'\"', '"'),
        'Add-Type -AssemblyName System.Speech',
        r'$s = New-Object System.Speech.Synthesis.SpeechSynthesizer',
        '\$s.Rate = $psRate',
        '\$bytes = [Convert]::FromBase64String("$encoded")',
        r'$text = [Text.Encoding]::UTF8.GetString($bytes)',
        r'$s.Speak($text)',
        r'$s.Dispose()',
      ].join('; ');
      try {
        _windowsProcess = await Process.start(
          'powershell.exe',
          <String>['-NoProfile', '-NonInteractive', '-Command', script],
          mode: ProcessStartMode.detachedWithStdio,
        );
        final process = _windowsProcess!;
        final code = await process.exitCode;
        if (identical(_windowsProcess, process)) _windowsProcess = null;
        return code == 0;
      } catch (_) {
        _windowsProcess = null;
        return false;
      }
    }
    return false;
  }

  static Future<void> stop() async {
    if (kIsWeb) return;

    _naturalGeneration++;
    final naturalDone = _naturalDone;
    _naturalDone = null;
    if (naturalDone != null && !naturalDone.isCompleted) naturalDone.complete();
    try {
      await _naturalPlayer.stop();
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod<void>('stop');
      } catch (_) {}
    }
    final process = _windowsProcess;
    _windowsProcess = null;
    if (process != null) process.kill();
  }

  static _SpeechProfile _profile(WesiAiMessageAuthor? author) => switch (author) {
        WesiAiMessageAuthor.zane => const _SpeechProfile(rate: 0.96, pitch: 0.90),
        WesiAiMessageAuthor.nirvana => const _SpeechProfile(rate: 1.00, pitch: 1.05),
        _ => const _SpeechProfile(rate: 1.00, pitch: 1.00),
      };
}

class _SpeechProfile {
  final double rate;
  final double pitch;

  const _SpeechProfile({required this.rate, required this.pitch});
}
