import '../models/wesi_ai_domain.dart';

class WesiAiProviderDescriptor {
  final String id;
  final String displayName;
  final Set<WesiAiCapability> capabilities;
  final bool available;
  final String? unavailableReason;

  const WesiAiProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.capabilities,
    required this.available,
    this.unavailableReason,
  });
}

class WesiAiContextPacket {
  final WesiAiConversation conversation;
  final List<WesiAiMessage> recentMessages;
  final String rollingSummary;
  final WesiAiConversationState state;

  const WesiAiContextPacket({
    required this.conversation,
    required this.recentMessages,
    required this.rollingSummary,
    required this.state,
  });
}

class WesiAiTextRequest {
  final WesiAiPersona persona;
  final String userText;
  final WesiAiContextPacket context;
  final List<WesiAiAttachment> attachments;

  const WesiAiTextRequest({
    required this.persona,
    required this.userText,
    required this.context,
    this.attachments = const [],
  });
}

class WesiAiTextChunk {
  final String text;
  final bool done;

  const WesiAiTextChunk(this.text, {this.done = false});
}

abstract interface class WesiAiProvider {
  WesiAiProviderDescriptor get descriptor;
}

abstract interface class WesiAiTextProvider implements WesiAiProvider {
  Stream<WesiAiTextChunk> complete(WesiAiTextRequest request);
}

abstract interface class WesiAiMediaProvider implements WesiAiProvider {
  Future<WesiAiGenerationJob> start({
    required WesiAiCapability capability,
    required WesiAiPersona persona,
    required String prompt,
    required WesiAiContextPacket context,
    List<WesiAiAttachment> attachments = const [],
    Map<String, Object?> parameters = const {},
  });

  Future<WesiAiGenerationJob> refresh(WesiAiGenerationJob job);

  Future<void> cancel(WesiAiGenerationJob job);
}

/// Реестр не выбирает модель сам: он только сообщает оркестратору, какие
/// способности реально доступны. Благодаря этому исчезновение генератора
/// видео не ломает текстовые ответы и изображения.
class WesiAiProviderRegistry {
  final List<WesiAiProvider> _providers;

  const WesiAiProviderRegistry(this._providers);

  Iterable<WesiAiProvider> supporting(WesiAiCapability capability) {
    return _providers.where((p) =>
        p.descriptor.available &&
        p.descriptor.capabilities.contains(capability));
  }

  WesiAiProvider? byId(String id) {
    for (final provider in _providers) {
      if (provider.descriptor.id == id) return provider;
    }
    return null;
  }
}
