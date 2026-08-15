enum WesiArtifactKind {
  text,
  json,
  pdf,
  zip,
  docx,
  xlsx,
  pptx,
  apk,
  windowsExecutable,
  png,
  jpeg,
  wav,
  mp3,
  video,
  sourceArchive,
  other,
}

enum WesiArtifactState {
  proposed,
  validating,
  validated,
  rejected,
  delivered,
}

class WesiArtifactDescriptor {
  final String id;
  final String relativePath;
  final WesiArtifactKind kind;
  final int? maxBytes;
  final String? displayName;
  final String? mimeType;

  /// Optional objective verification step that must have succeeded before
  /// this artifact can be validated/delivered. APK/EXE require build proof.
  final String? requiredSuccessfulStepId;

  const WesiArtifactDescriptor({
    required this.id,
    required this.relativePath,
    required this.kind,
    this.maxBytes,
    this.displayName,
    this.mimeType,
    this.requiredSuccessfulStepId,
  });
}

class WesiValidatedArtifact {
  final WesiArtifactDescriptor descriptor;
  final String canonicalPath;
  final int sizeBytes;
  final String sha256Hex;
  final DateTime validatedAt;
  final Map<String, dynamic> validationMetadata;

  const WesiValidatedArtifact({
    required this.descriptor,
    required this.canonicalPath,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.validatedAt,
    this.validationMetadata = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': descriptor.id,
        'relativePath': descriptor.relativePath,
        'kind': descriptor.kind.name,
        'canonicalPath': canonicalPath,
        'sizeBytes': sizeBytes,
        'sha256': sha256Hex,
        'validatedAt': validatedAt.toUtc().toIso8601String(),
        if (descriptor.displayName != null)
          'displayName': descriptor.displayName,
        if (descriptor.mimeType != null) 'mimeType': descriptor.mimeType,
        if (descriptor.requiredSuccessfulStepId != null)
          'requiredSuccessfulStepId': descriptor.requiredSuccessfulStepId,
        if (validationMetadata.isNotEmpty)
          'validationMetadata': validationMetadata,
      };
}

class WesiArtifactValidationResult {
  final bool ok;
  final String code;
  final String message;
  final WesiValidatedArtifact? artifact;

  const WesiArtifactValidationResult._({
    required this.ok,
    required this.code,
    required this.message,
    this.artifact,
  });

  const WesiArtifactValidationResult.failure(String code, String message)
      : this._(ok: false, code: code, message: message);

  const WesiArtifactValidationResult.success(WesiValidatedArtifact artifact)
      : this._(
          ok: true,
          code: 'OK',
          message: 'Artifact validated',
          artifact: artifact,
        );
}

class WesiArtifactDeliveryResult {
  final bool ok;
  final String code;
  final String message;
  final String? deliveryRef;

  const WesiArtifactDeliveryResult({
    required this.ok,
    required this.code,
    required this.message,
    this.deliveryRef,
  });

  const WesiArtifactDeliveryResult.success({String? deliveryRef})
      : this(
          ok: true,
          code: 'OK',
          message: 'Artifact delivered',
          deliveryRef: deliveryRef,
        );

  const WesiArtifactDeliveryResult.failure(String code, String message)
      : this(ok: false, code: code, message: message);
}

abstract class WesiArtifactDeliverySink {
  Future<WesiArtifactDeliveryResult> deliver(WesiValidatedArtifact artifact);
}

abstract class WesiArtifactExternalValidator {
  Future<WesiArtifactExternalValidation> validate({
    required WesiArtifactDescriptor descriptor,
    required String canonicalPath,
  });
}

class WesiArtifactExternalValidation {
  final bool ok;
  final String code;
  final String message;
  final Map<String, dynamic> metadata;

  const WesiArtifactExternalValidation({
    required this.ok,
    required this.code,
    required this.message,
    this.metadata = const <String, dynamic>{},
  });

  const WesiArtifactExternalValidation.success({
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) : this(
          ok: true,
          code: 'OK',
          message: 'External validator passed',
          metadata: metadata,
        );

  const WesiArtifactExternalValidation.failure(String code, String message)
      : this(ok: false, code: code, message: message);
}
