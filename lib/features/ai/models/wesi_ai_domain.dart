/// Базовые доменные типы Wesi AI.
///
/// Эти модели намеренно не знают о конкретных API и поставщиках. История,
/// персона и артефакты должны переживать замену любой базовой модели.
enum WesiAiPersona { zane, nirvana, lobby }

enum WesiAiRole { user, assistant, system, tool }

/// Сообщение — единица общей временной шкалы, а не только текстовый пузырь.
/// Генерация изображения, видео или аудио появляется в том же чате как
/// полноценное сообщение и обновляется по мере выполнения задания.
enum WesiAiMessageKind {
  text,
  generation,
  artifact,
  handoff,
  status,
  error,
}

enum WesiAiCapability {
  textChat,
  reasoning,
  code,
  visionUnderstanding,
  imageGeneration,
  imageEditing,
  videoGeneration,
  audioGeneration,
  speechToText,
  textToSpeech,
  fileAnalysis,
  webResearch,
}

enum WesiAiArtifactKind { image, video, audio, document, code, other }

enum WesiAiJobState {
  queued,
  running,
  waitingForProvider,
  completed,
  failed,
  cancelled,
}

/// Действия, доступные прямо на карточке результата в истории чата.
enum WesiAiGenerationAction {
  cancel,
  retry,
  regenerate,
  createVariation,
  edit,
  upscale,
  extend,
  download,
  useAsReference,
  continueDiscussion,
}

class WesiAiAttachment {
  final String id;
  final String name;
  final String mimeType;
  final String uri;
  final int? sizeBytes;

  const WesiAiAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.uri,
    this.sizeBytes,
  });
}

class WesiAiArtifact {
  final String id;
  final String conversationId;
  final String messageId;
  final WesiAiArtifactKind kind;
  final String uri;
  final String? previewUri;
  final String mimeType;
  final int? sizeBytes;
  final String? sha256;
  final String? providerJobId;
  final String prompt;
  final Map<String, Object?> parameters;
  final int version;
  final DateTime createdAt;

  const WesiAiArtifact({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.kind,
    required this.uri,
    required this.mimeType,
    required this.prompt,
    required this.createdAt,
    this.previewUri,
    this.sizeBytes,
    this.sha256,
    this.providerJobId,
    this.parameters = const {},
    this.version = 1,
  });
}

/// Состояние встроенной генерации, отображаемой прямо внутри сообщения.
/// Карточка сначала показывает очередь/прогресс, затем без создания новой
/// беседы превращается в готовый результат или ошибку с кнопкой повтора.
class WesiAiInlineGeneration {
  final String jobId;
  final WesiAiCapability capability;
  final WesiAiJobState state;
  final double? progress;
  final String prompt;
  final String? statusText;
  final String? error;
  final List<String> resultArtifactIds;
  final List<WesiAiGenerationAction> actions;

  const WesiAiInlineGeneration({
    required this.jobId,
    required this.capability,
    required this.state,
    required this.prompt,
    this.progress,
    this.statusText,
    this.error,
    this.resultArtifactIds = const [],
    this.actions = const [],
  });
}

class WesiAiMessage {
  final String id;
  final String conversationId;
  final WesiAiRole role;
  final WesiAiPersona? persona;
  final WesiAiMessageKind kind;
  final String text;
  final DateTime createdAt;
  final List<WesiAiAttachment> attachments;
  final List<String> artifactIds;
  final WesiAiInlineGeneration? generation;
  final String? replyToId;
  final String? providerId;
  final String? modelId;
  final Map<String, Object?> metadata;

  const WesiAiMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.persona,
    this.kind = WesiAiMessageKind.text,
    this.attachments = const [],
    this.artifactIds = const [],
    this.generation,
    this.replyToId,
    this.providerId,
    this.modelId,
    this.metadata = const {},
  });

  WesiAiMessage copyWith({
    String? text,
    WesiAiMessageKind? kind,
    List<WesiAiAttachment>? attachments,
    List<String>? artifactIds,
    WesiAiInlineGeneration? generation,
    String? providerId,
    String? modelId,
    Map<String, Object?>? metadata,
  }) {
    return WesiAiMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      persona: persona,
      kind: kind ?? this.kind,
      text: text ?? this.text,
      createdAt: createdAt,
      attachments: attachments ?? this.attachments,
      artifactIds: artifactIds ?? this.artifactIds,
      generation: generation ?? this.generation,
      replyToId: replyToId,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Сжатое состояние беседы, которое передаётся при смене персоны и модели.
class WesiAiConversationState {
  final String goal;
  final List<String> decisions;
  final List<String> openQuestions;
  final List<String> activeArtifactIds;
  final List<String> pendingJobIds;
  final Map<String, String> preferences;
  final String handoffSummary;

  const WesiAiConversationState({
    this.goal = '',
    this.decisions = const [],
    this.openQuestions = const [],
    this.activeArtifactIds = const [],
    this.pendingJobIds = const [],
    this.preferences = const {},
    this.handoffSummary = '',
  });

  WesiAiConversationState copyWith({
    String? goal,
    List<String>? decisions,
    List<String>? openQuestions,
    List<String>? activeArtifactIds,
    List<String>? pendingJobIds,
    Map<String, String>? preferences,
    String? handoffSummary,
  }) {
    return WesiAiConversationState(
      goal: goal ?? this.goal,
      decisions: decisions ?? this.decisions,
      openQuestions: openQuestions ?? this.openQuestions,
      activeArtifactIds: activeArtifactIds ?? this.activeArtifactIds,
      pendingJobIds: pendingJobIds ?? this.pendingJobIds,
      preferences: preferences ?? this.preferences,
      handoffSummary: handoffSummary ?? this.handoffSummary,
    );
  }
}

class WesiAiConversation {
  final String id;
  final String title;
  final WesiAiPersona activePersona;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String rollingSummary;
  final WesiAiConversationState state;
  final bool archived;

  const WesiAiConversation({
    required this.id,
    required this.title,
    required this.activePersona,
    required this.createdAt,
    required this.updatedAt,
    this.rollingSummary = '',
    this.state = const WesiAiConversationState(),
    this.archived = false,
  });

  WesiAiConversation copyWith({
    String? title,
    WesiAiPersona? activePersona,
    DateTime? updatedAt,
    String? rollingSummary,
    WesiAiConversationState? state,
    bool? archived,
  }) {
    return WesiAiConversation(
      id: id,
      title: title ?? this.title,
      activePersona: activePersona ?? this.activePersona,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rollingSummary: rollingSummary ?? this.rollingSummary,
      state: state ?? this.state,
      archived: archived ?? this.archived,
    );
  }
}

class WesiAiGenerationJob {
  final String id;
  final String conversationId;
  final String sourceMessageId;
  final String timelineMessageId;
  final WesiAiCapability capability;
  final WesiAiPersona requestedBy;
  final WesiAiJobState state;
  final double? progress;
  final String? providerId;
  final String? providerJobId;
  final List<String> resultArtifactIds;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WesiAiGenerationJob({
    required this.id,
    required this.conversationId,
    required this.sourceMessageId,
    required this.timelineMessageId,
    required this.capability,
    required this.requestedBy,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.progress,
    this.providerId,
    this.providerJobId,
    this.resultArtifactIds = const [],
    this.error,
  });
}
