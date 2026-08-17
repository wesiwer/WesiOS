import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

typedef HiveDirectoryResolver = Future<Directory> Function();

/// Prepares the single on-device Hive home used by WesiOS.
///
/// `Hive.initFlutter()` resolves the application documents directory but on
/// Windows that directory is not guaranteed to exist (for example after a
/// profile/Documents folder was removed or redirected). Hive then tries to
/// create the first `*.hive` file inside a missing parent and startup aborts
/// with `PathNotFoundException`.
///
/// WesiOS intentionally keeps using the exact same documents path rather
/// than silently falling back to another folder: changing the Hive home would
/// make existing local data look as if it disappeared.
class HiveStorageBootstrap {
  const HiveStorageBootstrap._();

  static Future<void> initialize({
    HiveDirectoryResolver? directoryResolver,
  }) async {
    if (kIsWeb) {
      await Hive.initFlutter();
      return;
    }

    final directory = await ensureStorageDirectory(
      directoryResolver: directoryResolver,
    );
    Hive.init(directory.path);
  }

  static Future<Directory> ensureStorageDirectory({
    HiveDirectoryResolver? directoryResolver,
  }) async {
    final resolver = directoryResolver ?? getApplicationDocumentsDirectory;
    final directory = await resolver();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    if (!await directory.exists()) {
      throw FileSystemException(
        'WesiOS local storage directory could not be created',
        directory.path,
      );
    }

    return directory;
  }
}
