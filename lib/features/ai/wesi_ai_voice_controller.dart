import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice input for the Wesi AI composer.
///
/// Speech is converted to text on the device/platform plugin first and only
/// the resulting text is sent through the normal authenticated Wesi AI chat
/// path. The controller never bypasses the regular chat permissions.
class WesiAiVoiceController extends ChangeNotifier {
  final SpeechToText _speech;

  WesiAiVoiceController({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  bool initialized = false;
  bool available = false;
  bool listening = false;
  String transcript = '';
  String? error;

  Future<bool> initialize() async {
    if (initialized) return available;
    error = null;
    try {
      available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: false,
      );
    } catch (e) {
      available = false;
      error = 'Голосовой ввод недоступен: $e';
    }
    initialized = true;
    notifyListeners();
    return available;
  }

  Future<void> start({String? localeId}) async {
    if (!await initialize()) return;
    if (_speech.isListening) await _speech.stop();
    transcript = '';
    error = null;
    listening = true;
    notifyListeners();
    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: localeId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      );
      listening = _speech.isListening;
    } catch (e) {
      listening = false;
      error = 'Не удалось начать распознавание речи: $e';
    }
    notifyListeners();
  }

  Future<String> stop() async {
    if (_speech.isListening) await _speech.stop();
    listening = false;
    notifyListeners();
    return transcript.trim();
  }

  Future<void> cancel() async {
    if (_speech.isListening) await _speech.cancel();
    listening = false;
    transcript = '';
    notifyListeners();
  }

  Future<void> toggle({String? localeId}) async {
    if (listening || _speech.isListening) {
      await stop();
    } else {
      await start(localeId: localeId);
    }
  }

  void clearTranscript() {
    transcript = '';
    notifyListeners();
  }

  void _onResult(SpeechRecognitionResult result) {
    transcript = result.recognizedWords.trim();
    if (result.finalResult) listening = false;
    notifyListeners();
  }

  void _onStatus(String status) {
    final normalized = status.toLowerCase();
    listening = normalized == 'listening';
    notifyListeners();
  }

  void _onError(SpeechRecognitionError speechError) {
    listening = false;
    error = speechError.errorMsg;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_speech.isListening) {
      _speech.cancel();
    }
    super.dispose();
  }
}
