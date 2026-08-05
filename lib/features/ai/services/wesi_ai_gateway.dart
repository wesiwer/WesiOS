import '../models/wesi_ai_domain.dart';
import 'wesi_ai_provider.dart';

/// Единственная сетевая граница Wesi AI в клиентском приложении.
///
/// Flutter-клиент не должен знать адреса и ключи внешних AI-провайдеров.
/// Он обращается только к зарубежному Wesi AI Gateway. Уже шлюз выбирает
/// текстовую, визуальную, видео- или аудиомодель и хранит её секреты.
class WesiAiGatewayConfig {
  static const String defaultBaseUrl = 'https://ai.wesi-inc.ru';

  final String baseUrl;

  /// Короткоживущий токен сотрудника/устройства WesiOS.
  /// Это не API-ключ внешней модели.
  final String accessToken;

  const WesiAiGatewayConfig({
    this.baseUrl = defaultBaseUrl,
    required this.accessToken,
  });

  Uri endpoint(String path) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalized$suffix');
  }
}

/// Универсальный запрос шлюзу.
///
/// Поле [capability] описывает требуемое действие, а не конкретного внешнего
/// поставщика. Благодаря этому модель можно заменить на сервере без выпуска
/// новой версии приложения.
class WesiAiGatewayRequest {
  final String conversationId;
  final WesiAiPersona persona;
  final WesiAiCapability capability;
  final WesiAiContextPacket context;
  final String prompt;
  final List<WesiAiAttachment> attachments;
  final Map<String, Object?> parameters;

  const WesiAiGatewayRequest({
    required this.conversationId,
    required this.persona,
    required this.capability,
    required this.context,
    required this.prompt,
    this.attachments = const [],
    this.parameters = const {},
  });

  Map<String, Object?> toJson() => {
        'conversation_id': conversationId,
        'persona': persona.name,
        'capability': capability.name,
        'prompt': prompt,
        'rolling_summary': context.rollingSummary,
        'state': {
          'goal': context.state.goal,
          'decisions': context.state.decisions,
          'open_questions': context.state.openQuestions,
          'active_artifact_ids': context.state.activeArtifactIds,
          'pending_job_ids': context.state.pendingJobIds,
          'preferences': context.state.preferences,
          'handoff_summary': context.state.handoffSummary,
        },
        'messages': [
          for (final message in context.recentMessages)
            {
              'id': message.id,
              'role': message.role.name,
              'persona': message.persona?.name,
              'text': message.text,
              'artifact_ids': message.artifactIds,
              'reply_to_id': message.replyToId,
            },
        ],
        'attachments': [
          for (final attachment in attachments)
            {
              'id': attachment.id,
              'name': attachment.name,
              'mime_type': attachment.mimeType,
              'uri': attachment.uri,
              'size_bytes': attachment.sizeBytes,
            },
        ],
        'parameters': parameters,
      };
}

/// Стабильные коды ошибок Wesi AI Gateway.
///
/// Клиент не должен зависеть от названий или ошибок конкретных внешних
/// провайдеров. Шлюз нормализует их в этот контракт.
enum WesiAiGatewayErrorCode {
  authRequired,
  forbidden,
  capabilityUnavailable,
  providerTimeout,
  rateLimit,
  jobFailed,
  resultExpired,
  invalidResponse,
  network,
}

class WesiAiGatewayException implements Exception {
  final WesiAiGatewayErrorCode code;
  final String message;
  final bool retryable;

  const WesiAiGatewayException({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  @override
  String toString() => 'WesiAiGatewayException(${code.name}): $message';
}

/// Транспорт вынесен отдельно, чтобы тестировать маршрутизацию и сериализацию
/// без реального зарубежного сервера.
abstract interface class WesiAiGatewayTransport {
  Stream<WesiAiTextChunk> streamText(
    WesiAiGatewayConfig config,
    WesiAiGatewayRequest request,
  );

  Future<WesiAiGenerationJob> startJob(
    WesiAiGatewayConfig config,
    WesiAiGatewayRequest request,
  );

  Future<WesiAiGenerationJob> refreshJob(
    WesiAiGatewayConfig config,
    WesiAiGenerationJob job,
  );

  Future<void> cancelJob(
    WesiAiGatewayConfig config,
    WesiAiGenerationJob job,
  );
}
