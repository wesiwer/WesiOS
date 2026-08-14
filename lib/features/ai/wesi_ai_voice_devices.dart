import 'package:flutter/foundation.dart';

import 'models/wesi_ai_chat_models.dart';
import 'wesi_ai_speech_output.dart';
import 'wesi_ai_voice_controller.dart';
import 'wesi_ai_voice_session.dart';

/// Настоящий микрофон в роли уха разговора.
///
/// Тонкая обёртка вокруг [WesiAiVoiceController]: разговор не должен знать
/// ни про разрешения, ни про плагин распознавания, а контроллер — ни про
/// то, что его слушают в цикле.
class WesiAiDeviceEar implements WesiAiVoiceEar {
  final WesiAiVoiceController controller;

  /// Язык распознавания. Разговор ведётся по-русски, и оставлять выбор
  /// системной локали нельзя: на устройстве с английской локалью русская
  /// речь распознаётся как бессмыслица.
  final String localeId;

  WesiAiDeviceEar(this.controller, {this.localeId = 'ru_RU'});

  @override
  Future<bool> start() async {
    await controller.start(localeId: localeId);
    return controller.available;
  }

  @override
  Future<void> stop() => controller.stop();

  @override
  Future<void> cancel() => controller.cancel();

  @override
  String get transcript => controller.transcript;

  @override
  bool get listening => controller.listening;

  @override
  void clearTranscript() => controller.clearTranscript();

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);
}

/// Настоящий синтез речи в роли рта разговора.
class WesiAiDeviceMouth implements WesiAiVoiceMouth {
  const WesiAiDeviceMouth();

  @override
  Future<void> speak(String text, {WesiAiMessageAuthor? author}) async {
    // Возвращаемое значение сознательно игнорируется: неудачная озвучка не
    // повод обрывать разговор. Человек увидит ответ текстом и сможет
    // продолжить голосом — это хуже, чем звучащий ответ, но несравнимо
    // лучше, чем разговор, который молча закончился.
    await WesiAiSpeechOutput.speak(text, author: author);
  }

  @override
  Future<void> stop() => WesiAiSpeechOutput.stop();
}
