import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'wesi_artifact_models.dart';

/// Trusted local delivery sink for Stage 9.
///
/// Only [WesiValidatedArtifact] values can enter this boundary. The file is
/// copied through a temporary path, hashed again and atomically renamed so a
/// stale or changed workspace artifact is never reported as delivered.
class WesiLocalArtifactDeliverySink implements WesiArtifactDeliverySink {
  final Directory deliveryRoot;

  const WesiLocalArtifactDeliverySink(this.deliveryRoot);

  @override
  Future<WesiArtifactDeliveryResult> deliver(
    WesiValidatedArtifact artifact,
  ) async {
    await deliveryRoot.create(recursive: true);
    final root = p.normalize(await deliveryRoot.resolveSymbolicLinks());
    final source = File(artifact.canonicalPath);
    if (!await source.exists()) {
      return const WesiArtifactDeliveryResult.failure(
        'ARTIFACT_SOURCE_MISSING',
        'Validated artifact disappeared before delivery',
      );
    }
    final currentDigest = await sha256.bind(source.openRead()).first;
    if (currentDigest.toString() != artifact.sha256Hex) {
      return const WesiArtifactDeliveryResult.failure(
        'ARTIFACT_CHANGED_AFTER_VALIDATION',
        'Artifact changed after validation',
      );
    }

    final safeId = artifact.descriptor.id.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final originalName = p.basename(artifact.canonicalPath);
    final outputName = '${safeId}_$originalName';
    final finalPath = p.normalize(p.join(root, outputName));
    if (!p.isWithin(root, finalPath)) {
      return const WesiArtifactDeliveryResult.failure(
        'ARTIFACT_DELIVERY_PATH_INVALID',
        'Artifact delivery path is invalid',
      );
    }
    if (await File(finalPath).exists()) {
      return const WesiArtifactDeliveryResult.failure(
        'ARTIFACT_DELIVERY_COLLISION',
        'Artifact delivery target already exists',
      );
    }

    final temp = File('$finalPath.tmp-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await source.openRead().pipe(temp.openWrite());
      final copiedDigest = await sha256.bind(temp.openRead()).first;
      if (copiedDigest.toString() != artifact.sha256Hex) {
        await temp.delete();
        return const WesiArtifactDeliveryResult.failure(
          'ARTIFACT_DELIVERY_HASH_MISMATCH',
          'Artifact checksum changed during delivery',
        );
      }
      await temp.rename(finalPath);
      return WesiArtifactDeliveryResult.success(deliveryRef: finalPath);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      return const WesiArtifactDeliveryResult.failure(
        'ARTIFACT_DELIVERY_FAILED',
        'Artifact could not be delivered safely',
      );
    }
  }
}
