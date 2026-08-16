import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_engine_path_guard.dart';

void main() {
  test('resolves a normal file inside engine root', () async {
    final root = await Directory.systemTemp.createTemp('wesi_engine_guard_');
    try {
      final output = File(
        '${root.path}${Platform.pathSeparator}outputs'
        '${Platform.pathSeparator}result.bin',
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(<int>[1, 2, 3], flush: true);
      final resolved = await WesiMediaEnginePathGuard.resolveOutput(
        root,
        'outputs/result.bin',
      );
      expect(resolved, isNotNull);
      expect(File(resolved!).absolute.path, output.absolute.path);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('rejects traversal, absolute and drive-qualified paths', () async {
    final root = await Directory.systemTemp.createTemp('wesi_engine_guard_bad_');
    try {
      expect(
        await WesiMediaEnginePathGuard.resolveOutput(root, '../secret.bin'),
        isNull,
      );
      expect(
        await WesiMediaEnginePathGuard.resolveOutput(root, '/tmp/secret.bin'),
        isNull,
      );
      expect(
        await WesiMediaEnginePathGuard.resolveOutput(root, r'C:\secret.bin'),
        isNull,
      );
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('rejects an in-root symlink that resolves outside engine root', () async {
    if (Platform.isWindows) return;
    final parent = await Directory.systemTemp.createTemp('wesi_engine_symlink_');
    final root = Directory('${parent.path}${Platform.pathSeparator}engine');
    final outside = File('${parent.path}${Platform.pathSeparator}outside.bin');
    try {
      await root.create(recursive: true);
      await outside.writeAsBytes(<int>[9, 8, 7], flush: true);
      final link = Link('${root.path}${Platform.pathSeparator}result.bin');
      await link.create(outside.path);
      final resolved = await WesiMediaEnginePathGuard.resolveOutput(
        root,
        'result.bin',
      );
      expect(resolved, isNull);
    } finally {
      if (await parent.exists()) await parent.delete(recursive: true);
    }
  });
}
