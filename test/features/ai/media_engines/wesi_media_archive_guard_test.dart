import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_archive_guard.dart';

void main() {
  test('accepts bounded relative entries', () {
    expect(
      () => WesiMediaArchiveGuard.validateEntries(
        const [
          WesiMediaArchiveEntry(name: 'runtime/launcher.bat', size: 1024, isSymbolicLink: false),
          WesiMediaArchiveEntry(name: 'models/model.bin', size: 4096, isSymbolicLink: false),
        ],
        compressedSizeBytes: 1024,
      ),
      returnsNormally,
    );
  });

  test('rejects path traversal', () {
    expect(
      () => WesiMediaArchiveGuard.validateEntries(
        const [WesiMediaArchiveEntry(name: '../escape.bin', size: 1, isSymbolicLink: false)],
        compressedSizeBytes: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects absolute Windows path', () {
    expect(
      () => WesiMediaArchiveGuard.validateEntries(
        const [WesiMediaArchiveEntry(name: r'C:\\escape.bin', size: 1, isSymbolicLink: false)],
        compressedSizeBytes: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects symbolic links', () {
    expect(
      () => WesiMediaArchiveGuard.validateEntries(
        const [WesiMediaArchiveEntry(name: 'runtime/link', size: 0, isSymbolicLink: true)],
        compressedSizeBytes: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects expansion bomb metadata', () {
    expect(
      () => WesiMediaArchiveGuard.validateEntries(
        const [WesiMediaArchiveEntry(name: 'models/huge.bin', size: 129000, isSymbolicLink: false)],
        compressedSizeBytes: 1000,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
