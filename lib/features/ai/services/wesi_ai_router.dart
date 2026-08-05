import '../data/wesi_ai_personas.dart';
import '../models/wesi_ai_domain.dart';

class WesiAiRouteDecision {
  final WesiAiPersona persona;
  final WesiAiCapability capability;
  final bool requiresHandoffConfirmation;
  final String reason;

  const WesiAiRouteDecision({
    required this.persona,
    required this.capability,
    required this.requiresHandoffConfirmation,
    required this.reason,
  });
}

/// Первый детерминированный маршрутизатор.
///
/// Он не пытается заменить модель-классификатор. Его задача — закрепить
/// правила передачи контекста и не допустить скрытой смены персоны. Позже
/// определение intent можно заменить, не меняя контракт решения.
class WesiAiRouter {
  const WesiAiRouter();

  WesiAiRouteDecision decide({
    required WesiAiPersona activePersona,
    required String text,
    List<WesiAiAttachment> attachments = const [],
    WesiAiCapability? explicitCapability,
    WesiAiPersona? explicitPersona,
  }) {
    final capability = explicitCapability ?? _detectCapability(text, attachments);
    final requestedPersona = explicitPersona ?? activePersona;

    if (requestedPersona == WesiAiPersona.lobby) {
      return WesiAiRouteDecision(
        persona: WesiAiPersona.lobby,
        capability: capability,
        requiresHandoffConfirmation: false,
        reason: 'Пользователь находится в совместной сессии Wesi AI.',
      );
    }

    final profile = WesiAiPersonas.byId(requestedPersona);
    if (profile.preferredCapabilities.contains(capability)) {
      return WesiAiRouteDecision(
        persona: requestedPersona,
        capability: capability,
        requiresHandoffConfirmation: false,
        reason: 'Задача соответствует специализации активной персоны.',
      );
    }

    final target = _preferredPersona(capability);
    return WesiAiRouteDecision(
      persona: target,
      capability: capability,
      requiresHandoffConfirmation: target != requestedPersona,
      reason: target == requestedPersona
          ? 'Активная персона может выполнить задачу через внешний инструмент.'
          : 'Задача лучше соответствует специализации ${WesiAiPersonas.byId(target).name}.',
    );
  }

  WesiAiPersona _preferredPersona(WesiAiCapability capability) {
    return switch (capability) {
      WesiAiCapability.imageGeneration ||
      WesiAiCapability.imageEditing ||
      WesiAiCapability.videoGeneration ||
      WesiAiCapability.audioGeneration ||
      WesiAiCapability.visionUnderstanding ||
      WesiAiCapability.textToSpeech => WesiAiPersona.nirvana,
      WesiAiCapability.code ||
      WesiAiCapability.reasoning ||
      WesiAiCapability.fileAnalysis ||
      WesiAiCapability.webResearch => WesiAiPersona.zane,
      _ => WesiAiPersona.zane,
    };
  }

  WesiAiCapability _detectCapability(
    String text,
    List<WesiAiAttachment> attachments,
  ) {
    final low = text.toLowerCase();
    final hasImage = attachments.any((a) => a.mimeType.startsWith('image/'));
    final hasAudio = attachments.any((a) => a.mimeType.startsWith('audio/'));

    if (hasImage) return WesiAiCapability.visionUnderstanding;
    if (hasAudio) return WesiAiCapability.speechToText;

    if (_containsAny(low, const ['сгенерируй видео', 'создай видео', 'анимацию'])) {
      return WesiAiCapability.videoGeneration;
    }
    if (_containsAny(low, const ['сгенерируй изображение', 'создай картинку', 'нарисуй'])) {
      return WesiAiCapability.imageGeneration;
    }
    if (_containsAny(low, const ['измени изображение', 'отредактируй фото', 'убери с фото'])) {
      return WesiAiCapability.imageEditing;
    }
    if (_containsAny(low, const ['создай музыку', 'сгенерируй аудио', 'озвучь'])) {
      return WesiAiCapability.audioGeneration;
    }
    if (_containsAny(low, const ['код', 'рефактор', 'ошибка сборки', 'функция', 'класс'])) {
      return WesiAiCapability.code;
    }
    if (_containsAny(low, const ['рассчитай', 'посчитай', 'проанализируй', 'прогноз'])) {
      return WesiAiCapability.reasoning;
    }
    return WesiAiCapability.textChat;
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }
}
