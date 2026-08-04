import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/sysadmin/models/monitor_target.dart';
import 'package:wesios/features/sysadmin/models/probe_result.dart';
import 'package:wesios/features/sysadmin/services/network_probe.dart';

/// Модуль системного администратора показывает цифры, по которым человек
/// решает, всё ли в порядке с сервером. Ошибка здесь — это либо ложная
/// тревога среди ночи, либо молчание, когда сервер уже лежит.
void main() {
  final base = DateTime.utc(2026, 8, 4, 12);

  ProbeSample up(int ms, {int shift = 0}) => ProbeSample(
        at: base.add(Duration(seconds: shift)),
        outcome: ProbeOutcome.up,
        latency: Duration(microseconds: ms * 1000),
      );

  ProbeSample down({int shift = 0}) => ProbeSample(
        at: base.add(Duration(seconds: shift)),
        outcome: ProbeOutcome.timeout,
      );

  group('сводка по замерам', () {
    test('пустая сводка ничего не выдумывает', () {
      const stats = ProbeStats.empty;
      expect(stats.isEmpty, isTrue);
      expect(stats.avgMs, isNull);
      expect(stats.minMs, isNull);
      expect(stats.jitterMs, isNull);
      expect(stats.grade, HealthGrade.unknown);
    });

    test('минимум, среднее и максимум считаются по ответившим', () {
      final stats = ProbeStats([up(10), up(30), down(), up(20)]);
      expect(stats.minMs, 10);
      expect(stats.maxMs, 30);
      expect(stats.avgMs, closeTo(20, 0.001));
      expect(stats.total, 4);
      expect(stats.lost, 1);
      expect(stats.loss, closeTo(0.25, 0.001));
    });

    test('разброс считается между соседними, а не от среднего', () {
      // 20, 200, 20, 200 — среднее приличное, но связь рвётся рывками.
      // Отклонение от среднего дало бы 90; между соседними — 180, и это
      // честнее описывает, что человек почувствует.
      final stats = ProbeStats([up(20), up(200), up(20), up(200)]);
      expect(stats.jitterMs, closeTo(180, 0.001));
    });

    test('одного замера мало, чтобы говорить о разбросе', () {
      expect(ProbeStats([up(10)]).jitterMs, isNull);
    });

    test('быстро и стабильно — это «работает»', () {
      final stats = ProbeStats([for (var i = 0; i < 10; i++) up(25, shift: i)]);
      expect(stats.grade, HealthGrade.good);
    });

    test('десятая часть потерь — уже перебои', () {
      final stats = ProbeStats([
        for (var i = 0; i < 9; i++) up(25, shift: i),
        down(shift: 9),
      ]);
      expect(stats.loss, closeTo(0.1, 0.001));
      expect(stats.grade, HealthGrade.degraded);
    });

    test('очень медленные ответы — тоже перебои, хотя ответы есть', () {
      final stats =
          ProbeStats([for (var i = 0; i < 10; i++) up(1500, shift: i)]);
      expect(stats.grade, HealthGrade.degraded);
    });

    test('рваная связь — перебои даже без потерь', () {
      final stats = ProbeStats([
        for (var i = 0; i < 10; i++) up(i.isEven ? 20 : 600, shift: i),
      ]);
      expect(stats.loss, 0);
      expect(stats.grade, HealthGrade.degraded,
          reason: 'разброс в сотни миллисекунд — это не «всё хорошо»');
    });

    test('не отвечает — это «лежит»', () {
      final stats = ProbeStats([for (var i = 0; i < 6; i++) down(shift: i)]);
      expect(stats.grade, HealthGrade.down);
    });

    test('поднявшийся сервер показывает «работает», а не «лежит»', () {
      // Полчаса лежал, потом поднялся. Оценка по всему окну держала бы
      // тревогу ещё долго после того, как всё починилось.
      final stats = ProbeStats([
        for (var i = 0; i < 20; i++) down(shift: i),
        for (var i = 20; i < 25; i++) up(30, shift: i),
      ]);
      expect(stats.grade, isNot(HealthGrade.down));
    });

    test('нет сети у устройства — это не «сервер лежит»', () {
      // Разница принципиальная: иначе человек поедет чинить работающий
      // сервер, у которого всё в порядке.
      final stats = ProbeStats([
        up(30),
        ProbeSample(at: base, outcome: ProbeOutcome.offline),
      ]);
      expect(stats.grade, HealthGrade.offline);
    });
  });

  group('сертификат', () {
    TlsInfo cert(int daysFromNow) => TlsInfo(
          subject: 'CN=sync.example.ru',
          issuer: "C=US, O=Let's Encrypt, CN=R3",
          validUntil: base.add(Duration(days: daysFromNow)),
        );

    test('свежий сертификат тревоги не поднимает', () {
      expect(cert(60).expiringSoon(base), isFalse);
      expect(cert(60).expired(base), isFalse);
      expect(cert(60).daysLeft(base), 60);
    });

    test('две недели до конца — пора беспокоиться', () {
      // Let's Encrypt обновляет за 30 дней до конца. Если осталось 14 —
      // автопродление не сработало, и узнать об этом надо сейчас, а не в
      // день, когда сайт перестанет открываться.
      expect(cert(14).expiringSoon(base), isTrue);
      expect(cert(15).expiringSoon(base), isFalse);
    });

    test('истёкший распознаётся как истёкший', () {
      expect(cert(-1).expired(base), isTrue);
      expect(cert(0).expired(base), isTrue);
    });
  });

  group('показатели с агента', () {
    // Ровно то, что печатает server/wesios-agent.sh — проверено запуском.
    const real = '''
{
  "at": "2026-08-04T09:19:48Z",
  "load1": 0.25,
  "cores": 4,
  "mem_used_mb": 709,
  "mem_total_mb": 16075,
  "disk_used_gb": 12,
  "disk_total_gb": 252,
  "uptime_sec": 20638
}''';

    test('настоящий вывод агента разбирается', () {
      final load =
          ServerLoad.tryParse(jsonDecode(real) as Map<String, dynamic>)!;
      expect(load.load1, 0.25);
      expect(load.cores, 4);
      expect(load.memUsedMb, 709);
      expect(load.uptime.inHours, 5);
    });

    test('загрузка делится на число ядер', () {
      // load 2.0 на восьми ядрах — это четверть, а на одном — двойная
      // очередь. Голое число без второго ничего не значит.
      final eight = ServerLoad.tryParse({
        'at': base.toIso8601String(),
        'load1': 2.0,
        'cores': 8,
      })!;
      final one = ServerLoad.tryParse({
        'at': base.toIso8601String(),
        'load1': 2.0,
        'cores': 1,
      })!;
      expect(eight.cpuFraction, closeTo(0.25, 0.001));
      expect(one.cpuFraction, closeTo(2.0, 0.001));
    });

    test('без обязательных полей не разбирается, а не подставляет нули', () {
      expect(ServerLoad.tryParse({'cores': 4}), isNull);
      expect(ServerLoad.tryParse({'load1': 1.0}), isNull,
          reason: 'без времени замера нельзя понять, свежие ли это цифры');
    });

    test('старые цифры распознаются как старые', () {
      final load = ServerLoad.tryParse({
        'at': base.toIso8601String(),
        'load1': 0.1,
        'cores': 1,
      })!;
      expect(load.isStale(base.add(const Duration(minutes: 5))), isFalse);
      expect(load.isStale(base.add(const Duration(minutes: 30))), isTrue);
    });

    test('деление на ноль не роняет экран', () {
      final load = ServerLoad.tryParse({
        'at': base.toIso8601String(),
        'load1': 0.5,
        'cores': 0,
        'mem_total_mb': 0,
        'disk_total_gb': 0,
      })!;
      expect(load.cpuFraction, 0);
      expect(load.memFraction, 0);
      expect(load.diskFraction, 0);
    });
  });

  group('наблюдаемый узел', () {
    test('переживает круг через JSON', () {
      const t = MonitorTarget(
        id: 't1',
        name: 'Сервер СПб',
        host: 'sync.example.ru',
        port: 8090,
        url: 'https://sync.example.ru/',
        loadUrl: 'https://sync.example.ru/wesios-status.json',
        kind: TargetKind.site,
        checkTls: true,
      );
      final back = MonitorTarget.tryParse(t.toJson())!;
      expect(back.id, t.id);
      expect(back.name, t.name);
      expect(back.host, t.host);
      expect(back.port, 8090);
      expect(back.url, t.url);
      expect(back.loadUrl, t.loadUrl);
      expect(back.kind, TargetKind.site);
      expect(back.checkTls, isTrue);
    });

    test('без адреса — не узел', () {
      expect(MonitorTarget.tryParse({'id': 'x'}), isNull);
      expect(MonitorTarget.tryParse({'id': 'x', 'host': '   '}), isNull);
      expect(MonitorTarget.tryParse({'host': 'example.ru'}), isNull);
    });

    test('без названия подставляется адрес, а не пустая строка', () {
      final t = MonitorTarget.tryParse({'id': 'x', 'host': 'example.ru'})!;
      expect(t.name, 'example.ru');
    });

    test('copyWith умеет стирать необязательное поле', () {
      // Без метки «не передано» нельзя отличить «оставь как было» от
      // «сотри» — та же ловушка, что была в статьях базы знаний.
      const t = MonitorTarget(
          id: 't', name: 'x', host: 'h', loadUrl: 'https://a/b.json');
      expect(t.copyWith(name: 'y').loadUrl, 'https://a/b.json');
      expect(t.copyWith(loadUrl: null).loadUrl, isNull);
    });
  });

  group('замеры вживую', () {
    test('несуществующее имя распознаётся как проблема с именем', () async {
      final sample = await NetworkProbe.tcp(
        'this-host-does-not-exist.wesios-test.invalid',
        443,
        timeout: const Duration(seconds: 3),
      );
      expect(sample.ok, isFalse);
      expect(sample.outcome, ProbeOutcome.dnsFailed,
          reason: 'иначе человек пойдёт чинить сервер вместо записи DNS');
    });

    test('закрытый порт на себе самом распознаётся как отказ', () async {
      // Порт из динамического диапазона, на котором заведомо никто не
      // слушает: соединение отвергается сразу, без ожидания.
      final sample = await NetworkProbe.tcp('127.0.0.1', 59999,
          timeout: const Duration(seconds: 3));
      expect(sample.ok, isFalse);
      expect(sample.outcome, ProbeOutcome.refused,
          reason: 'закрытый порт — это не таймаут: служба не запущена');
    });

    test('замер до самого себя занимает разумное время', () async {
      final result =
          await NetworkProbe.dns('localhost', timeout: const Duration(seconds: 3));
      expect(result.ok, isTrue);
      expect(result.addresses, isNotEmpty);
    });
  });
}
