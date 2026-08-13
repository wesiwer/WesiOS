import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Передача файла между устройствами в одной сети.
///
/// Самый частый и самый быстрый случай: студия, офис, дом — оба устройства в
/// одном Wi-Fi. Файл идёт напрямую, на скорости сети, сервер не участвует
/// вовсе. Через интернет так надёжно не выйдет: у сотовых операторов почти
/// поголовно общий внешний адрес на многих абонентов, и пробить его удаётся
/// не всегда.
///
/// Отдающая сторона поднимает временный сервер на случайном порту и отдаёт
/// файл ровно один раз — по одноразовому пропуску. Принимающая скачивает и
/// сверяет отпечаток: файл, дошедший наполовину, ничем не отличается от
/// целого, пока его не попробуешь открыть.
class LocalFileTransfer {
  /// Сколько живёт предложение, если за ним не пришли.
  ///
  /// Открытый сервер на устройстве — это дверь, и держать её открытой
  /// дольше нужного незачем. Десять минут покрывают «увидел уведомление,
  /// дошёл до телефона, нажал».
  static const Duration offerLifetime = Duration(minutes: 10);

  static final Random _random = Random.secure();

  /// Одноразовый пропуск: 32 случайных байта.
  ///
  /// Ссылка гуляет через синхронизацию, а та проходит через сервер. Пропуск
  /// делает бесполезной саму по себе перехваченную ссылку без второго
  /// условия — быть в той же сети.
  static String newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Отпечаток файла. По нему принимающая сторона понимает, что получила
  /// именно то и целиком.
  static Future<String> checksumOf(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return 'sha256:$digest';
  }

  /// Поднять раздачу одного файла.
  ///
  /// Возвращает то, что нужно передать другой стороне: адрес, пропуск,
  /// размер и отпечаток. Сервер закрывается сам — после первой удачной
  /// выдачи или по истечении срока.
  static Future<LocalTransferOffer> serve({
    required File file,
    required String requestId,
    Duration lifetime = offerLifetime,
    InternetAddress? bindTo,
  }) async {
    if (!await file.exists()) {
      throw const FileSystemException('Файл не найден');
    }
    final token = newToken();
    final checksum = await checksumOf(file);
    final size = await file.length();

    final server = await HttpServer.bind(
      bindTo ?? InternetAddress.anyIPv4,
      0,
      shared: false,
    );

    final done = Completer<void>();
    Timer? expiry;

    Future<void> close() async {
      expiry?.cancel();
      if (!done.isCompleted) done.complete();
      await server.close(force: true);
    }

    expiry = Timer(lifetime, close);

    server.listen(
      (request) async {
        // Единственный правильный запрос: GET по своему пути со своим
        // пропуском. Всё остальное — либо ошибка, либо чужой интерес, и в
        // обоих случаях ответ один.
        final ok = request.method == 'GET' &&
            request.uri.path == '/file' &&
            request.uri.queryParameters['token'] == token;
        if (!ok) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        try {
          request.response.headers.contentType = ContentType.binary;
          request.response.headers.contentLength = size;
          request.response.headers.set('X-Wesi-Checksum', checksum);
          await request.response.addStream(file.openRead());
          await request.response.close();
        } catch (_) {
          // Обрыв на середине — не повод оставлять дверь открытой навсегда,
          // но и не повод закрывать её до срока: пусть попробуют ещё раз.
          return;
        }
        await close();
      },
      onError: (_) => close(),
      cancelOnError: false,
    );

    return LocalTransferOffer(
      requestId: requestId,
      port: server.port,
      token: token,
      checksum: checksum,
      sizeBytes: size,
      expiresAt: DateTime.now().add(lifetime),
      close: close,
      finished: done.future,
    );
  }

  /// Забрать файл по предложению.
  ///
  /// Пишем во временный файл и переименовываем только после сверки
  /// отпечатка: наполовину скачанный wav выглядит как обычный файл, и
  /// обнаружится это в самый неподходящий момент.
  static Future<LocalTransferResult> fetch({
    required String host,
    required int port,
    required String token,
    required String expectedChecksum,
    required File saveTo,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final partial = File('${saveTo.path}.part');
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/file',
        queryParameters: {'token': token},
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return LocalTransferResult.failure(
          'Устройство отказало в выдаче файла (${response.statusCode})',
        );
      }

      await saveTo.parent.create(recursive: true);
      final sink = partial.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }

      final actual = await checksumOf(partial);
      if (actual != expectedChecksum) {
        await partial.delete();
        return LocalTransferResult.failure(
          'Файл дошёл повреждённым — отпечаток не совпал',
        );
      }
      if (await saveTo.exists()) await saveTo.delete();
      await partial.rename(saveTo.path);
      return LocalTransferResult.success(
        path: saveTo.path,
        sizeBytes: await saveTo.length(),
        checksum: actual,
      );
    } on TimeoutException {
      return LocalTransferResult.failure('Передача не уложилась во время');
    } on SocketException {
      return LocalTransferResult.failure('Устройство недоступно в этой сети');
    } catch (e) {
      return LocalTransferResult.failure('Не удалось получить файл: $e');
    } finally {
      client.close(force: true);
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {
          // Недоудалённый обрывок — мелочь на фоне того, что файл не дошёл.
        }
      }
    }
  }

  /// Свои адреса в локальных сетях.
  ///
  /// Только частные диапазоны: адрес из интернета сюда попасть не должен —
  /// раздача рассчитана на «мы в одном Wi-Fi», а не на «меня видно всем».
  static Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (isPrivateIPv4(a.address)) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Адрес из частного диапазона: 10/8, 172.16/12, 192.168/16 или
  /// 169.254/16 (когда устройства соединились напрямую, без роутера).
  static bool isPrivateIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }
}

/// Открытая раздача одного файла.
class LocalTransferOffer {
  final String requestId;
  final int port;
  final String token;
  final String checksum;
  final int sizeBytes;
  final DateTime expiresAt;

  /// Закрыть раздачу досрочно.
  final Future<void> Function() close;

  /// Завершится, когда файл выдан или срок вышел.
  final Future<void> finished;

  const LocalTransferOffer({
    required this.requestId,
    required this.port,
    required this.token,
    required this.checksum,
    required this.sizeBytes,
    required this.expiresAt,
    required this.close,
    required this.finished,
  });

  /// То, что уезжает другой стороне через синхронизацию.
  ///
  /// Адрес не входит: его подставляет получатель из того, что видит в своей
  /// сети. Хранить в общей записи домашний адрес устройства незачем.
  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'port': port,
        'token': token,
        'checksum': checksum,
        'sizeBytes': sizeBytes,
        'expiresAt': expiresAt.toIso8601String(),
      };
}

class LocalTransferResult {
  final bool ok;
  final String path;
  final int sizeBytes;
  final String checksum;
  final String error;

  const LocalTransferResult.success({
    required this.path,
    required this.sizeBytes,
    required this.checksum,
  })  : ok = true,
        error = '';

  const LocalTransferResult.failure(this.error)
      : ok = false,
        path = '',
        sizeBytes = 0,
        checksum = '';
}
