import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/probe_result.dart';

/// Замеры до сервера и домена.
///
/// **Почему не настоящий ping.** ICMP требует сырых сокетов: на Android без
/// root их не открыть, на Windows нужны права администратора. Вместо этого
/// замеряется время установления TCP-соединения с портом, который на сервере
/// и так открыт. Число получается чуть больше икмп-пинга (добавляется
/// рукопожатие TCP), но меряет оно ровно то, что важно: за сколько сервер
/// реально начинает отвечать. И работает везде одинаково, без прав.
///
/// Это честнее, чем рисовать «ping 24 мс», добытый неизвестно откуда.
class NetworkProbe {
  /// Сколько ждать ответа. Больше пяти секунд ждать бессмысленно: если
  /// сервер не ответил за это время, пользоваться им всё равно нельзя.
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// Замер до порта.
  static Future<ProbeSample> tcp(
    String host,
    int port, {
    Duration timeout = defaultTimeout,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      watch.stop();
      return ProbeSample(
        at: at,
        outcome: ProbeOutcome.up,
        latency: watch.elapsed,
      );
    } on SocketException catch (e) {
      watch.stop();
      return ProbeSample(at: at, outcome: _classify(e), detail: e.osError?.message);
    } on TimeoutException {
      return ProbeSample(at: at, outcome: ProbeOutcome.timeout);
    } catch (e) {
      return ProbeSample(
          at: at, outcome: ProbeOutcome.timeout, detail: e.toString());
    } finally {
      // Соединение закрывается сразу: нам нужно было только время до ответа,
      // а открытый сокет на той стороне — лишняя запись в журнале сервера.
      await socket?.close().catchError((_) {});
      socket?.destroy();
    }
  }

  /// Разбор причины отказа.
  ///
  /// Все три случая для человека разные: «имя не разрешается» — чинить DNS,
  /// «порт закрыт» — служба не запущена, «нет сети» — дело в самом
  /// устройстве. Одно общее «недоступен» отправило бы чинить не то.
  static ProbeOutcome _classify(SocketException e) {
    final code = e.osError?.errorCode;
    final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();

    if (text.contains('failed host lookup') ||
        text.contains('nodename nor servname') ||
        text.contains('name or service not known') ||
        text.contains('no address associated')) {
      return ProbeOutcome.dnsFailed;
    }
    // 111 — ECONNREFUSED в Linux, 61 — в macOS, 10061 — в Windows.
    if (code == 111 || code == 61 || code == 10061 ||
        text.contains('connection refused')) {
      return ProbeOutcome.refused;
    }
    // 101/10051 — сети нет вовсе.
    if (code == 101 || code == 10051 ||
        text.contains('network is unreachable')) {
      return ProbeOutcome.offline;
    }
    return ProbeOutcome.timeout;
  }

  /// Разрешение имени в адреса и время, которое это заняло.
  static Future<({List<String> addresses, Duration took, bool ok})> dns(
    String host, {
    Duration timeout = defaultTimeout,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final found = await InternetAddress.lookup(host).timeout(timeout);
      watch.stop();
      return (
        addresses: [for (final a in found) a.address],
        took: watch.elapsed,
        ok: found.isNotEmpty,
      );
    } catch (_) {
      watch.stop();
      return (addresses: <String>[], took: watch.elapsed, ok: false);
    }
  }

  /// Проверка сайта: код ответа и время до него.
  static Future<ProbeSample> http(
    String url, {
    Duration timeout = defaultTimeout,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return ProbeSample(
          at: at, outcome: ProbeOutcome.dnsFailed, detail: 'Плохой адрес');
    }

    final client = HttpClient()..connectionTimeout = timeout;
    final watch = Stopwatch()..start();
    try {
      // GET, а не HEAD: часть серверов на HEAD отвечает 405, и сайт выглядел
      // бы сломанным, будучи полностью рабочим.
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close().timeout(timeout);
      watch.stop();
      await res.drain<void>();

      final code = res.statusCode;
      if (code >= 200 && code < 400) {
        return ProbeSample(
          at: at,
          outcome: ProbeOutcome.up,
          latency: watch.elapsed,
          detail: 'HTTP $code',
        );
      }
      return ProbeSample(
        at: at,
        outcome: ProbeOutcome.badResponse,
        latency: watch.elapsed,
        detail: 'HTTP $code',
      );
    } on HandshakeException catch (e) {
      return ProbeSample(
          at: at, outcome: ProbeOutcome.tlsFailed, detail: e.message);
    } on SocketException catch (e) {
      return ProbeSample(at: at, outcome: _classify(e));
    } on TimeoutException {
      return ProbeSample(at: at, outcome: ProbeOutcome.timeout);
    } catch (e) {
      return ProbeSample(
          at: at, outcome: ProbeOutcome.timeout, detail: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// Сертификат домена: кому выдан, кем и до какого числа.
  ///
  /// Смысл — увидеть заранее, что автопродление не сработало. Сертификат,
  /// истёкший ночью, обнаруживается утром по тому, что сайт не открывается
  /// вообще ни у кого.
  static Future<TlsInfo?> tls(
    String host, {
    int port = 443,
    Duration timeout = defaultTimeout,
  }) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(host, port, timeout: timeout,
          onBadCertificate: (_) {
        // Просроченный или чужой сертификат нам всё равно надо прочитать —
        // ровно затем, чтобы о нём сообщить. Отказ здесь означал бы, что
        // самая важная для этой проверки ситуация не отображается никак.
        return true;
      });
      final cert = socket.peerCertificate;
      if (cert == null) return null;
      return TlsInfo(
        subject: cert.subject,
        issuer: cert.issuer,
        validUntil: cert.endValidity,
      );
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// Показатели самого сервера — их даёт агент, установленный на нём.
  ///
  /// Изнутри приложения загрузку процессора и память чужой машины узнать
  /// нельзя никак: сеть про это ничего не сообщает. Либо на сервере что-то
  /// эти цифры отдаёт, либо их нет — и рисовать их «примерно» было бы
  /// обманом. Скрипт агента лежит в `server/wesios-agent.sh`.
  static Future<ServerLoadProbe> load(
    String url, {
    Duration timeout = defaultTimeout,
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return const ServerLoadProbe.failed(
        ServerLoadFailure.badAddress,
        'Адрес нельзя разобрать.',
      );
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return ServerLoadProbe.failed(
          ServerLoadFailure.httpError,
          'Сервер ответил ${res.statusCode}.',
          statusCode: res.statusCode,
        );
      }
      final body = await res.transform(utf8.decoder).join();
      final Object? json;
      try {
        json = jsonDecode(body);
      } catch (_) {
        // Ровно этот случай и притворялся молчанием агента: по адресу
        // отвечала страница портала, а не файл агента. Разница видна только
        // здесь, и не сказать о ней — значит отправить человека чинить
        // работающий агент вместо неправильного адреса.
        return ServerLoadProbe.failed(
          ServerLoadFailure.notJson,
          _looksLikeHtml(body)
              ? 'По адресу отвечает веб-страница, а не агент.'
              : 'Ответ не разбирается как JSON.',
          statusCode: 200,
        );
      }
      if (json is! Map<String, dynamic>) {
        return const ServerLoadProbe.failed(
          ServerLoadFailure.notJson,
          'Ответ не разбирается как JSON.',
          statusCode: 200,
        );
      }
      final parsed = ServerLoad.tryParse(json);
      if (parsed == null) {
        return const ServerLoadProbe.failed(
          ServerLoadFailure.wrongShape,
          'Это JSON, но без полей агента (load1, at).',
          statusCode: 200,
        );
      }
      return ServerLoadProbe.ok(parsed);
    } catch (error) {
      return ServerLoadProbe.failed(
        ServerLoadFailure.unreachable,
        'Узел не отвечает: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeHtml(String body) {
    final head = body.trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }
}

/// Почему показателей сервера нет.
///
/// Раньше все причины сходились в один `null`, и интерфейс говорил «агент не
/// отвечает» одинаково и когда узел молчал, и когда по адресу лежала совсем
/// другая страница. Это разные поломки с разным лечением: в первом случае
/// чинят агент, во втором — адрес.
enum ServerLoadFailure {
  badAddress,
  unreachable,
  httpError,
  notJson,
  wrongShape,
}

/// Результат опроса агента: либо показатели, либо причина их отсутствия.
class ServerLoadProbe {
  final ServerLoad? load;
  final ServerLoadFailure? failure;
  final String detail;
  final int? statusCode;

  const ServerLoadProbe.ok(ServerLoad this.load)
      : failure = null,
        detail = '',
        statusCode = 200;

  const ServerLoadProbe.failed(
    this.failure,
    this.detail, {
    this.statusCode,
  }) : load = null;

  bool get isOk => load != null;
}

/// Показатели, присланные агентом с сервера.
class ServerLoad {
  /// Средняя загрузка за минуту — та самая первая цифра из `uptime`.
  final double load1;
  final int cores;
  final int memUsedMb;
  final int memTotalMb;
  final int diskUsedGb;
  final int diskTotalGb;
  final Duration uptime;
  final DateTime measuredAt;

  const ServerLoad({
    required this.load1,
    required this.cores,
    required this.memUsedMb,
    required this.memTotalMb,
    required this.diskUsedGb,
    required this.diskTotalGb,
    required this.uptime,
    required this.measuredAt,
  });

  /// Загрузка в долях от числа ядер. 1.0 — процессор занят целиком.
  ///
  /// Именно с делением на ядра: load 2.0 на восьмиядерной машине — это
  /// четверть, а на одноядерной — двойная очередь. Показывать голую цифру
  /// значит показывать число, которое без второго числа ничего не значит.
  double get cpuFraction => cores <= 0 ? 0 : load1 / cores;

  double get memFraction => memTotalMb <= 0 ? 0 : memUsedMb / memTotalMb;

  double get diskFraction => diskTotalGb <= 0 ? 0 : diskUsedGb / diskTotalGb;

  /// Данные устарели — агент перестал их обновлять.
  bool isStale(DateTime now) =>
      now.difference(measuredAt) > const Duration(minutes: 10);

  static ServerLoad? tryParse(Map<String, dynamic> json) {
    double? num_(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v');
    int? int_(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

    final load1 = num_(json['load1']);
    final measured = DateTime.tryParse('${json['at']}');
    if (load1 == null || measured == null) return null;

    return ServerLoad(
      load1: load1,
      cores: int_(json['cores']) ?? 1,
      memUsedMb: int_(json['mem_used_mb']) ?? 0,
      memTotalMb: int_(json['mem_total_mb']) ?? 0,
      diskUsedGb: int_(json['disk_used_gb']) ?? 0,
      diskTotalGb: int_(json['disk_total_gb']) ?? 0,
      uptime: Duration(seconds: int_(json['uptime_sec']) ?? 0),
      measuredAt: measured,
    );
  }
}
