import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/monitor_target.dart';
import '../models/probe_result.dart';
import 'network_probe.dart';

/// Список наблюдаемых узлов и накопленные по ним замеры.
///
/// Замеры живут только в памяти и умирают вместе с программой. Это осознанно:
/// история пингов за месяц — это база данных, кольцевой буфер и разговор про
/// место на диске, а нужна она затем, чтобы посмотреть «что сейчас». Когда
/// понадобится история — её место на сервере, а не в телефоне.
class MonitorService {
  static const String _box = 'wesios_settings';
  static const String _key = 'sysadmin_targets';

  /// Сколько замеров держим на узел. Шестьдесят при опросе раз в секунду —
  /// это минута живой картины, ровно столько, сколько человек смотрит на
  /// экран, прежде чем решить, что всё в порядке.
  static const int windowSize = 60;

  /// Меняется при правке списка узлов.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Меняется на каждый новый замер — по нему перерисовываются графики.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static final Map<String, List<ProbeSample>> _history = {};
  static final Map<String, TlsInfo?> _tls = {};
  static final Map<String, ServerLoad?> _load = {};

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ список

  static List<MonitorTarget> get targets {
    final raw = _open()?.get(_key);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>)
            if (MonitorTarget.tryParse(e) case final t?) t,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(List<MonitorTarget> list) async {
    await _open()?.put(_key, jsonEncode([for (final t in list) t.toJson()]));
    revision.value++;
  }

  static Future<void> add(MonitorTarget target) async {
    await _save([...targets, target]);
  }

  static Future<void> update(MonitorTarget target) async {
    await _save([
      for (final t in targets)
        if (t.id == target.id) target else t,
    ]);
  }

  static Future<void> remove(String id) async {
    _history.remove(id);
    _tls.remove(id);
    _load.remove(id);
    await _save([
      for (final t in targets)
        if (t.id != id) t,
    ]);
  }

  static MonitorTarget? byId(String id) {
    for (final t in targets) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ------------------------------------------------------------------ замеры

  static ProbeStats statsOf(String id) => ProbeStats(_history[id] ?? const []);

  static TlsInfo? tlsOf(String id) => _tls[id];

  static ServerLoad? loadOf(String id) => _load[id];

  static void _record(String id, ProbeSample sample) {
    final list = _history.putIfAbsent(id, () => <ProbeSample>[]);
    list.add(sample);
    if (list.length > windowSize) {
      list.removeRange(0, list.length - windowSize);
    }
    tick.value++;
  }

  /// Один проход по узлу: время ответа, а для сайта — ещё и код.
  static Future<ProbeSample> probe(MonitorTarget target) async {
    final sample = target.kind == TargetKind.site && target.url != null
        ? await NetworkProbe.http(target.url!)
        : await NetworkProbe.tcp(target.host, target.port);
    _record(target.id, sample);
    return sample;
  }

  /// Медленные проверки: сертификат и загрузка с агента.
  ///
  /// Отдельно от [probe] намеренно — их незачем делать раз в секунду.
  /// Сертификат меняется раз в три месяца, агент пишет цифры раз в минуту.
  static Future<void> refreshSlow(MonitorTarget target) async {
    if (target.checkTls) {
      _tls[target.id] = await NetworkProbe.tls(target.host, port: target.port);
    }
    final loadUrl = target.loadUrl;
    if (loadUrl != null && loadUrl.trim().isNotEmpty) {
      _load[target.id] = await NetworkProbe.load(loadUrl);
    }
    tick.value++;
  }

  /// Пройтись по всем узлам разом — для списка на главном экране модуля.
  static Future<void> probeAll() async {
    // Последовательно, а не разом: пять одновременных соединений с телефона
    // на плохой связи мешают друг другу, и замер меряет уже не сервер, а
    // собственную очередь.
    for (final t in targets) {
      await probe(t);
    }
  }

  /// Забыть накопленное — при выходе из модуля.
  static void clearHistory() {
    _history.clear();
    _tls.clear();
    _load.clear();
  }
}

/// Живой пинг: повторяющийся замер с окном.
///
/// Отдельный объект, а не метод сервиса, потому что у него есть жизнь:
/// запустили, посмотрели, остановили. Таймер, который забыли остановить,
/// продолжает дёргать сервер, когда экран давно закрыт.
class LivePing {
  final MonitorTarget target;
  final Duration interval;

  Timer? _timer;
  bool _inFlight = false;

  LivePing(this.target, {this.interval = const Duration(seconds: 1)});

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    // Первый замер сразу: ждать секунду перед первой цифрой — значит секунду
    // показывать пустой экран.
    unawaited(_once());
    _timer = Timer.periodic(interval, (_) => unawaited(_once()));
  }

  Future<void> _once() async {
    // Если предыдущий замер ещё идёт (сервер тормозит), новый не начинаем:
    // иначе на медленном узле замеры наложатся друг на друга и будут мерить
    // сами себя.
    if (_inFlight) return;
    _inFlight = true;
    try {
      await MonitorService.probe(target);
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
