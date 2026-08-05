import '../models/wesi_ai_domain.dart';

/// Изменение одной карточки генерации в общей временной шкале чата.
///
/// UI подписывается на этот поток и заменяет состояние существующего
/// сообщения: очередь → прогресс → результат/ошибка. Отдельный экран для
/// выполнения генерации не требуется.
class WesiAiTimelinePatch {
  final String conversationId;
  final String messageId;
  final WesiAiMessage replacement;

  const WesiAiTimelinePatch({
    required this.conversationId,
    required this.messageId,
    required this.replacement,
  });
}

abstract interface class WesiAiTimelineStore {
  Future<void> append(WesiAiMessage message);
  Future<void> replace(String messageId, WesiAiMessage message);
  Future<WesiAiMessage?> find(String messageId);
  Stream<List<WesiAiMessage>> watchConversation(String conversationId);
}

abstract interface class WesiAiGenerationJobStore {
  Future<void> save(WesiAiGenerationJob job);
  Future<WesiAiGenerationJob?> find(String jobId);
  Stream<WesiAiGenerationJob> watch(String jobId);
}

/// Координатор, превращающий медиазапрос в сообщение внутри текущего чата.
///
/// Последовательность:
/// 1. пользовательское сообщение уже добавлено в timeline;
/// 2. создаётся assistant-сообщение WesiAiMessageKind.generation;
/// 3. в нём отображаются persona, prompt, очередь и действия отмены;
/// 4. provider обновляет job, а координатор обновляет то же сообщение;
/// 5. после завершения карточка содержит артефакты и действия продолжения.
class WesiAiInlineGenerationCoordinator {
  final WesiAiTimelineStore timeline;
  final WesiAiGenerationJobStore jobs;

  const WesiAiInlineGenerationCoordinator({
    required this.timeline,
    required this.jobs,
  });

  Future<WesiAiGenerationJob> createPlaceholder({
    required String jobId,
    required String messageId,
    required String sourceMessageId,
    required String conversationId,
    required WesiAiPersona persona,
    required WesiAiCapability capability,
    required String prompt,
    required DateTime now,
  }) async {
    final inline = WesiAiInlineGeneration(
      jobId: jobId,
      capability: capability,
      state: WesiAiJobState.queued,
      prompt: prompt,
      statusText: 'Подготавливаю генерацию…',
      actions: const [WesiAiGenerationAction.cancel],
    );

    final message = WesiAiMessage(
      id: messageId,
      conversationId: conversationId,
      role: WesiAiRole.assistant,
      persona: persona,
      kind: WesiAiMessageKind.generation,
      text: '',
      createdAt: now,
      generation: inline,
    );

    final job = WesiAiGenerationJob(
      id: jobId,
      conversationId: conversationId,
      sourceMessageId: sourceMessageId,
      timelineMessageId: messageId,
      capability: capability,
      requestedBy: persona,
      state: WesiAiJobState.queued,
      createdAt: now,
      updatedAt: now,
    );

    await timeline.append(message);
    await jobs.save(job);
    return job;
  }

  Future<void> applyJobUpdate(WesiAiGenerationJob job) async {
    final current = await timeline.find(job.timelineMessageId);
    if (current == null) return;

    final completed = job.state == WesiAiJobState.completed;
    final failed = job.state == WesiAiJobState.failed;

    final actions = <WesiAiGenerationAction>[
      if (!completed && !failed && job.state != WesiAiJobState.cancelled)
        WesiAiGenerationAction.cancel,
      if (failed || job.state == WesiAiJobState.cancelled)
        WesiAiGenerationAction.retry,
      if (completed) ...const [
        WesiAiGenerationAction.regenerate,
        WesiAiGenerationAction.createVariation,
        WesiAiGenerationAction.download,
        WesiAiGenerationAction.useAsReference,
        WesiAiGenerationAction.continueDiscussion,
      ],
      if (completed && job.capability == WesiAiCapability.imageGeneration)
        WesiAiGenerationAction.edit,
      if (completed && job.capability == WesiAiCapability.videoGeneration)
        WesiAiGenerationAction.extend,
    ];

    final generation = WesiAiInlineGeneration(
      jobId: job.id,
      capability: job.capability,
      state: job.state,
      prompt: current.generation?.prompt ?? '',
      progress: job.progress,
      statusText: _status(job.state),
      error: job.error,
      resultArtifactIds: job.resultArtifactIds,
      actions: actions,
    );

    await timeline.replace(
      current.id,
      current.copyWith(
        kind: completed ? WesiAiMessageKind.artifact : WesiAiMessageKind.generation,
        artifactIds: job.resultArtifactIds,
        generation: generation,
        providerId: job.providerId,
      ),
    );
  }

  String _status(WesiAiJobState state) => switch (state) {
        WesiAiJobState.queued => 'В очереди',
        WesiAiJobState.running => 'Генерирую…',
        WesiAiJobState.waitingForProvider => 'Ожидаю результат модели…',
        WesiAiJobState.completed => 'Готово',
        WesiAiJobState.failed => 'Не удалось сгенерировать',
        WesiAiJobState.cancelled => 'Генерация отменена',
      };
}
