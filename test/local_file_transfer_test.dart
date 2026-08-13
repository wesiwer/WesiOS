import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/files/services/local_file_transfer.dart';

/// Передача идёт по-настоящему: поднимается сервер, открывается сокет, файл
/// проходит через сеть. Подделывать здесь нечего — именно сетевая часть и
/// ломается в жизни, а поддельная передача проверяла бы только сама себя.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wesios_transfer');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File makeFile(String name, int bytes) {
    final file = File('${dir.path}/$name')..createSync(recursive: true);
    // Не нули: одинаковые байты скрыли бы ошибку в сборке файла по кускам.
    file.writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(bytes, (i) => (i * 31) % 256)),
    );
    return file;
  }

  test('файл доходит целиком и совпадает побайтно', () async {
    final source = makeFile('beat.wav', 512 * 1024);
    final offer = await LocalFileTransfer.serve(
      file: source,
      requestId: 'R1',
      bindTo: InternetAddress.loopbackIPv4,
    );

    final target = File('${dir.path}/received/beat.wav');
    final result = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: offer.token,
      expectedChecksum: offer.checksum,
      saveTo: target,
    );

    expect(result.ok, isTrue, reason: result.error);
    expect(result.sizeBytes, source.lengthSync());
    expect(target.readAsBytesSync(), source.readAsBytesSync());
    await offer.close();
  });

  test('без пропуска файл не отдаётся', () async {
    final source = makeFile('beat.wav', 4096);
    final offer = await LocalFileTransfer.serve(
      file: source,
      requestId: 'R1',
      bindTo: InternetAddress.loopbackIPv4,
    );

    final result = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: 'подобранный-пропуск',
      expectedChecksum: offer.checksum,
      saveTo: File('${dir.path}/stolen.wav'),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('отказал'));
    expect(File('${dir.path}/stolen.wav').existsSync(), isFalse);
    await offer.close();
  });

  test('раздача закрывается после первой выдачи', () async {
    final source = makeFile('beat.wav', 8192);
    final offer = await LocalFileTransfer.serve(
      file: source,
      requestId: 'R1',
      bindTo: InternetAddress.loopbackIPv4,
    );

    final first = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: offer.token,
      expectedChecksum: offer.checksum,
      saveTo: File('${dir.path}/first.wav'),
    );
    expect(first.ok, isTrue);
    await offer.finished;

    // Второй раз по той же ссылке — уже некуда стучаться. Пропуск
    // одноразовый, и дверь закрылась.
    final second = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: offer.token,
      expectedChecksum: offer.checksum,
      saveTo: File('${dir.path}/second.wav'),
    );
    expect(second.ok, isFalse);
  });

  test('подменённый файл не принимается', () async {
    final source = makeFile('beat.wav', 4096);
    final offer = await LocalFileTransfer.serve(
      file: source,
      requestId: 'R1',
      bindTo: InternetAddress.loopbackIPv4,
    );

    final target = File('${dir.path}/received.wav');
    final result = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: offer.token,
      expectedChecksum: 'sha256:совсем-другой-отпечаток',
      saveTo: target,
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('отпечаток'));
    expect(target.existsSync(), isFalse,
        reason: 'наполовину скачанный файл не должен остаться под своим '
            'именем — он выглядит как целый, пока его не откроешь');
  });

  test('недоступное устройство не роняет попытку', () async {
    final result = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: 1, // здесь никто не слушает
      token: 'x',
      expectedChecksum: 'sha256:x',
      saveTo: File('${dir.path}/nothing.wav'),
    );
    expect(result.ok, isFalse);
    expect(result.error, isNotEmpty);
  });

  test('срок раздачи истекает сам', () async {
    final source = makeFile('beat.wav', 1024);
    final offer = await LocalFileTransfer.serve(
      file: source,
      requestId: 'R1',
      bindTo: InternetAddress.loopbackIPv4,
      lifetime: const Duration(milliseconds: 120),
    );
    await offer.finished;

    final result = await LocalFileTransfer.fetch(
      host: '127.0.0.1',
      port: offer.port,
      token: offer.token,
      expectedChecksum: offer.checksum,
      saveTo: File('${dir.path}/late.wav'),
    );
    expect(result.ok, isFalse,
        reason: 'открытая дверь на устройстве не должна оставаться навсегда');
  });

  test('несуществующий файл не поднимает раздачу', () async {
    expect(
      () => LocalFileTransfer.serve(
        file: File('${dir.path}/нет-такого.wav'),
        requestId: 'R1',
        bindTo: InternetAddress.loopbackIPv4,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('пропуск каждый раз новый и достаточно длинный', () {
    final tokens = {for (var i = 0; i < 50; i++) LocalFileTransfer.newToken()};
    expect(tokens.length, 50, reason: 'повтор пропуска — это чужой доступ');
    expect(tokens.every((t) => t.length >= 40), isTrue);
  });

  group('частные адреса', () {
    test('свои сети распознаются', () {
      for (final a in ['10.0.0.5', '172.16.3.1', '172.31.255.254',
          '192.168.1.7', '169.254.10.2']) {
        expect(LocalFileTransfer.isPrivateIPv4(a), isTrue, reason: a);
      }
    });

    test('адреса из интернета — нет', () {
      // Раздача рассчитана на «мы в одном Wi-Fi», а не на «меня видно всем».
      for (final a in ['8.8.8.8', '172.32.0.1', '172.15.0.1', '193.168.1.1',
          'не адрес', '1.2.3']) {
        expect(LocalFileTransfer.isPrivateIPv4(a), isFalse, reason: a);
      }
    });
  });

  test('отпечаток считается по содержимому, а не по имени', () async {
    final a = makeFile('a.wav', 2048);
    final b = File('${dir.path}/b.wav')
      ..writeAsBytesSync(a.readAsBytesSync());
    expect(await LocalFileTransfer.checksumOf(a),
        await LocalFileTransfer.checksumOf(b));

    b.writeAsBytesSync([...a.readAsBytesSync(), 1]);
    expect(await LocalFileTransfer.checksumOf(a),
        isNot(await LocalFileTransfer.checksumOf(b)));
  });
}
