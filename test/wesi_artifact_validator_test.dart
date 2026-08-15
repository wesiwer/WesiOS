import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wesios/features/ai/runtime/wesi_artifact_delivery.dart';
import 'package:wesios/features/ai/runtime/wesi_artifact_models.dart';
import 'package:wesios/features/ai/runtime/wesi_artifact_validator.dart';

void main() {
  test('validates bounded UTF-8 artifact and computes checksum', () async {
    final root = await Directory.systemTemp.createTemp('wesi-artifact-');
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'result.txt'));
    await file.writeAsString('verified output');

    final result = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'text-1',
        relativePath: 'result.txt',
        kind: WesiArtifactKind.text,
      ),
      workspaceRoot: root.path,
    );

    expect(result.ok, isTrue);
    expect(result.artifact, isNotNull);
    expect(result.artifact!.sizeBytes, greaterThan(0));
    expect(result.artifact!.sha256Hex.length, 64);
  });

  test('rejects path traversal and protected .wesi state', () async {
    final root = await Directory.systemTemp.createTemp('wesi-artifact-');
    addTearDown(() => root.delete(recursive: true));

    final traversal = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'bad-1',
        relativePath: '../outside.txt',
        kind: WesiArtifactKind.text,
      ),
      workspaceRoot: root.path,
    );
    final internal = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'bad-2',
        relativePath: '.wesi/state.json',
        kind: WesiArtifactKind.json,
      ),
      workspaceRoot: root.path,
    );

    expect(traversal.code, 'ARTIFACT_PATH_FORBIDDEN');
    expect(internal.code, 'ARTIFACT_PATH_FORBIDDEN');
  });

  test('rejects symlink escape when platform supports links', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('wesi-artifact-root-');
    final outside = await Directory.systemTemp.createTemp('wesi-artifact-out-');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    final outsideFile = File(p.join(outside.path, 'secret.txt'));
    await outsideFile.writeAsString('secret');
    await Link(p.join(root.path, 'link.txt')).create(outsideFile.path);

    final result = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'link-1',
        relativePath: 'link.txt',
        kind: WesiArtifactKind.text,
      ),
      workspaceRoot: root.path,
    );

    expect(result.code, 'ARTIFACT_SYMLINK_ESCAPE');
  });

  test('complex artifact requires trusted external validator', () async {
    final root = await Directory.systemTemp.createTemp('wesi-artifact-');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'app.apk')).writeAsBytes(<int>[0x50, 0x4B, 0x03, 0x04]);

    final result = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'apk-1',
        relativePath: 'app.apk',
        kind: WesiArtifactKind.apk,
      ),
      workspaceRoot: root.path,
    );

    expect(result.code, 'ARTIFACT_EXTERNAL_VALIDATOR_REQUIRED');
  });

  test('delivery refuses file changed after validation', () async {
    final root = await Directory.systemTemp.createTemp('wesi-artifact-');
    final delivery = await Directory.systemTemp.createTemp('wesi-delivery-');
    addTearDown(() async {
      await root.delete(recursive: true);
      await delivery.delete(recursive: true);
    });
    final file = File(p.join(root.path, 'result.txt'));
    await file.writeAsString('version one');
    final validated = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'text-2',
        relativePath: 'result.txt',
        kind: WesiArtifactKind.text,
      ),
      workspaceRoot: root.path,
    );
    expect(validated.ok, isTrue);
    await file.writeAsString('version two');

    final delivered = await WesiLocalArtifactDeliverySink(delivery)
        .deliver(validated.artifact!);
    expect(delivered.ok, isFalse);
    expect(delivered.code, 'ARTIFACT_CHANGED_AFTER_VALIDATION');
  });

  test('delivery re-hashes and publishes validated file atomically', () async {
    final root = await Directory.systemTemp.createTemp('wesi-artifact-');
    final delivery = await Directory.systemTemp.createTemp('wesi-delivery-');
    addTearDown(() async {
      await root.delete(recursive: true);
      await delivery.delete(recursive: true);
    });
    final file = File(p.join(root.path, 'result.txt'));
    await file.writeAsString('deliver me');
    final validated = await const WesiArtifactValidator().validate(
      descriptor: const WesiArtifactDescriptor(
        id: 'text-3',
        relativePath: 'result.txt',
        kind: WesiArtifactKind.text,
      ),
      workspaceRoot: root.path,
    );

    final delivered = await WesiLocalArtifactDeliverySink(delivery)
        .deliver(validated.artifact!);
    expect(delivered.ok, isTrue);
    expect(delivered.deliveryRef, isNotNull);
    expect(await File(delivered.deliveryRef!).readAsString(), 'deliver me');
  });
}
