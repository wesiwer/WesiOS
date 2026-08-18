import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_artifact_store.dart';

void main() {
  test('promotes bytes into an app-owned opaque artifact with hash', () async {
    final temp = await Directory.systemTemp.createTemp('wesi_artifact_store_');
    final sourceDir = Directory('${temp.path}${Platform.pathSeparator}engine');
    final storeDir = Directory('${temp.path}${Platform.pathSeparator}store');
    final source =
        File('${sourceDir.path}${Platform.pathSeparator}raw-output.png');
    const bytes = <int>[1, 3, 3, 7, 9, 11];
    try {
      await sourceDir.create(recursive: true);
      await source.writeAsBytes(bytes, flush: true);
      final result = await WesiMediaArtifactStore.promote(
        sourcePath: source.absolute.path,
        mediaType: 'image',
        mimeType: 'image/png',
        rootDirectory: storeDir,
      );
      expect(result.ok, isTrue);
      expect(result.code, 'OK');
      expect(result.path, isNot(source.absolute.path));
      expect(result.path!.startsWith(storeDir.absolute.path), isTrue);
      expect(await File(result.path!).readAsBytes(), bytes);
      expect(result.byteSize, bytes.length);
      expect(result.mimeType, 'image/png');
      expect(result.sha256Hex, sha256.convert(bytes).toString());
      expect(await source.exists(), isTrue);
      expect(
        storeDir
            .listSync(recursive: true)
            .whereType<File>()
            .any((file) => file.path.endsWith('.part')),
        isFalse,
      );
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('rejects a MIME type outside the selected media class', () async {
    final temp = await Directory.systemTemp.createTemp('wesi_artifact_mime_');
    final source = File('${temp.path}${Platform.pathSeparator}payload.txt');
    try {
      await source.writeAsString('not an image', flush: true);
      final result = await WesiMediaArtifactStore.promote(
        sourcePath: source.absolute.path,
        mediaType: 'image',
        mimeType: 'text/plain',
        rootDirectory: Directory('${temp.path}${Platform.pathSeparator}store'),
      );
      expect(result.ok, isFalse);
      expect(result.code, 'WAI_MEDIA_ARTIFACT_MIME_FORBIDDEN');
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('rejects empty output before creating a durable artifact', () async {
    final temp = await Directory.systemTemp.createTemp('wesi_artifact_empty_');
    final source = File('${temp.path}${Platform.pathSeparator}empty.mp3');
    final store = Directory('${temp.path}${Platform.pathSeparator}store');
    try {
      await source.create();
      final result = await WesiMediaArtifactStore.promote(
        sourcePath: source.absolute.path,
        mediaType: 'music',
        mimeType: 'audio/mpeg',
        rootDirectory: store,
      );
      expect(result.ok, isFalse);
      expect(result.code, 'WAI_MEDIA_ARTIFACT_SIZE_INVALID');
      expect(await store.exists(), isFalse);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
