import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/wesi_ai_chat_models.dart';

/// Low-latency local speech output for assistant replies.
///
/// Android uses the native `wesios/ai_speech` bridge. Windows uses the OS
/// `System.Speech` synthesizer. No provider key and no shell-interpolated user
/// text is involved; Windows receives only a base64 UTF-8 payload.
class WesiAiSpeechOutput {
  static const MethodChannel _androidChannel = MethodChannel('wesios/ai_speech');
  static Process? _windowsProcess;

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
        final code = await _windowsProcess!.exitCode;
        _windowsProcess = null;
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
