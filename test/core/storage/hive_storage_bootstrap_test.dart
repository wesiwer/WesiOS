import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/storage/hive_storage_bootstrap.dart';

void main() {
  test('creates a missing Hive parent directory recursively', () async {
    final root = await Directory.systemTemp.createTemp('wesios_hive_bootstrap_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final missingDocuments = Directory(
      '${root.path}${Platform.pathSeparator}profile'
      '${Platform.pathSeparator}Documents',
    );
    expect(await missingDocuments.exists(), isFalse);

    final resolved = await HiveStorageBootstrap.ensureStorageDirectory(
      directoryResolver: () async => missingDocuments,
    );

    expect(resolved.path, missingDocuments.path);
    expect(await missingDocuments.exists(), isTrue);
  });

  test('keeps an existing Hive directory unchanged', () async {
    final existing = await Directory.systemTemp.createTemp(
      'wesios_hive_existing_',
    );
    addTearDown(() async {
      if (await existing.exists()) {
        await existing.delete(recursive: true);
      }
    });

    final marker = File(
      '${existing.path}${Platform.pathSeparator}existing-data.marker',
    );
    await marker.writeAsString('keep');

    final resolved = await HiveStorageBootstrap.ensureStorageDirectory(
      directoryResolver: () async => existing,
    );

    expect(resolved.path, existing.path);
    expect(await marker.readAsString(), 'keep');
  });
}
