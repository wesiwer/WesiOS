import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/monitor_target.dart';
import 'models/probe_result.dart';
import 'services/monitor_service.dart';
import 'services/network_probe.dart';
import 'widgets/health_dot.dart';
import 'widgets/target_editor_sheet.dart';

/// Карточка узла: живой пинг и всё, что про него известно.
///
/// Живой опрос идёт, **только пока открыт этот экран**. Таймер, оставленный
/// работать в фоне, дёргал бы сервер круглые сутки и разряжал бы телефон
/// ради цифры, на которую никто не смотрит.
class TargetDetailScreen extends StatefulWidget {
  final String targetId;

  const TargetDetailScreen({super.key, required this.targetId});

  static Future<void> open(BuildContext context, String id) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TargetDetailScreen(targetId: id)),
      );

  @override
  State<TargetDetailScreen> createState() => _TargetDetailScreenState();
}

class _TargetDetailScreenState extends State<TargetDetailScreen> {
  LivePing? _ping;
  List<String> _addresses = const [];
  Duration? _dnsTook;
  bool _dnsOk = true;

  bool get _ru => WesiLocale.isRussian;

  MonitorTarget? get _target => MonitorService.byId(widget.targetId);

  @override
  void initState() {
    super.initState();
    final t = _target;
    if (t == null) return;
    _ping = LivePing(t)..start();
    _lookup(t);
    MonitorService.refreshSlow(t);
  }

  @override
  void dispose() {
    _ping?.stop();
    super.dispose();
  }

  Future<void> _lookup(MonitorTarget t) async {
    final result = await NetworkProbe.dns(t.host);
    if (!mounted) return;
    setState(() {
      _addresses = result.addresses;
      _dnsTook = result.took;
      _dnsOk = result.ok;
    });
  }

  Future<void> _edit(MonitorTarget t) async {
    _ping?.stop();
    await TargetEditorSheet.show(context, initial: t);
    if (!mounted) return;
    final updated = _target;
    if (updated == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _ping = LivePing(updated)..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    if (t == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(_ru ? 'Узел удалён' : 'Target removed',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: MonitorService.tick,
      builder: (context, _, __) {
        final stats = MonitorService.statsOf(t.id);
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(t, stats),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _liveCard(stats),
                      const SizedBox(height: 12),
                      _numbers(stats),
                      const SizedBox(height: 12),
                      _dnsCard(),
                      if (t.checkTls) ...[
                        const SizedBox(height: 12),
                        _tlsCard(t),
                      ],
                      const SizedBox(height: 12),
                      _loadCard(t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(MonitorTarget t, ProbeStats stats) => Padding(
        padding: EdgeInsets.fromLTRB(
            8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            HealthDot(grade: stats.grade),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WesiTitle(t.name, size: 18),
                  Text('${t.host}:${t.port}',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: _ru ? 'Изменить' : 'Edit',
              icon: Icon(Icons.tune, size: 19, color: AppTheme.textMuted),
              onPressed: () => _edit(t),
            ),
          ],
        ),
      );

  Widget _liveCard(ProbeStats stats) {
    final last = stats.last;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined,
                  size: 16, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(
                _ru ? 'Пинг в прямом эфире' : 'Live ping',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary),
              ),
              const Spacer(),
              if (last != null)
                Text(
                  last.ok
                      ? '${last.ms!.round()} ${_ru ? 'мс' : 'ms'}'
                      : last.describe(russian: _ru),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color:
                        last.ok ? AppTheme.textPrimary : AppTheme.accentRed,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LiveChart(stats),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _ru
                ? 'Замеряется время установления TCP-соединения: настоящий '
                    'ICMP-пинг требует прав, которых у приложения на телефоне '
                    'нет. Число чуть больше, но меряет то же самое — за '
                    'сколько узел начинает отвечать.'
                : 'This measures TCP connect time: a real ICMP ping needs '
                    'privileges a phone app does not have. Slightly higher, '
                    'but it measures the same thing.',
            style: TextStyle(
                fontSize: 10.5, height: 1.4, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _numbers(ProbeStats stats) {
    String ms(double? v) => v == null ? '—' : '${v.round()}';
    return Row(
      children: [
        _metric(_ru ? 'Мин' : 'Min', ms(stats.minMs)),
        const SizedBox(width: 8),
        _metric(_ru ? 'Средн' : 'Avg', ms(stats.avgMs)),
        const SizedBox(width: 8),
        _metric(_ru ? 'Макс' : 'Max', ms(stats.maxMs)),
        const SizedBox(width: 8),
        _metric(_ru ? 'Разброс' : 'Jitter', ms(stats.jitterMs)),
        const SizedBox(width: 8),
        _metric(
          _ru ? 'Потери' : 'Loss',
          '${(stats.loss * 100).round()}%',
          alarming: stats.loss >= 0.1,
        ),
      ],
    );
  }

  Widget _dnsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(Icons.travel_explore,
                _ru ? 'Разрешение имени' : 'Name resolution'),
            const SizedBox(height: 9),
            if (!_dnsOk)
              Text(
                _ru
                    ? 'Имя не разрешается в адрес. Проверьте A-запись у '
                        'регистратора домена.'
                    : 'Name does not resolve. Check the A record at your '
                        'registrar.',
                style: TextStyle(fontSize: 12, color: AppTheme.accentRed),
              )
            else ...[
              for (final a in _addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('→ $a',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textPrimary)),
                ),
              if (_dnsTook != null)
                Text(
                  '${_ru ? 'заняло' : 'took'} ${_dnsTook!.inMilliseconds} '
                  '${_ru ? 'мс' : 'ms'}',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
            ],
          ],
        ),
      );

  Widget _tlsCard(MonitorTarget t) {
    final tls = MonitorService.tlsOf(t.id);
    final now = DateTime.now();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.lock_outline, _ru ? 'Сертификат' : 'Certificate'),
          const SizedBox(height: 9),
          if (tls == null)
            Text(
              _ru
                  ? 'Не удалось прочитать — узел не отвечает по TLS на этом '
                      'порту.'
                  : 'Could not read — no TLS on this port.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            )
          else ...[
            _row(_ru ? 'Кем выдан' : 'Issuer', tls.issuer),
            _row(_ru ? 'Действует до' : 'Valid until',
                tls.validUntil.toLocal().toString().split('.').first),
            const SizedBox(height: 6),
            Text(
              tls.expired(now)
                  ? (_ru ? 'ИСТЁК' : 'EXPIRED')
                  : (_ru
                      ? 'Осталось ${tls.daysLeft(now)} дн.'
                      : '${tls.daysLeft(now)} days left'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: tls.expiringSoon(now)
                    ? AppTheme.accentRed
                    : AppTheme.accentGreen,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loadCard(MonitorTarget t) {
    final load = MonitorService.loadOf(t.id);
    final now = DateTime.now();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.speed, _ru ? 'Загрузка сервера' : 'Server load'),
          const SizedBox(height: 9),
          if (t.loadUrl == null || t.loadUrl!.trim().isEmpty)
            Text(
              _ru
                  ? 'Агент не подключён. Загрузку процессора, память и диск '
                      'чужой машины из сети узнать нельзя — их присылает '
                      'агент, установленный на самом сервере. Скрипт: '
                      'server/wesios-agent.sh'
                  : 'No agent. CPU, memory and disk cannot be read over the '
                      'network — an agent on the server reports them. See '
                      'server/wesios-agent.sh',
              style: TextStyle(
                  fontSize: 11.5, height: 1.45, color: AppTheme.textMuted),
            )
          else if (load == null)
            Text(
              _ru
                  ? 'Агент указан, но не отвечает по этому адресу.'
                  : 'Agent configured but not responding.',
              style: TextStyle(fontSize: 12, color: AppTheme.accentRed),
            )
          else ...[
            if (load.isStale(now))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _ru
                      ? 'Цифры устарели — агент перестал их обновлять.'
                      : 'Numbers are stale — the agent stopped updating.',
                  style:
                      TextStyle(fontSize: 11.5, color: AppTheme.accentRed),
                ),
              ),
            _bar(_ru ? 'Процессор' : 'CPU', load.cpuFraction,
                '${load.load1.toStringAsFixed(2)} / ${load.cores}'),
            const SizedBox(height: 8),
            _bar(_ru ? 'Память' : 'Memory', load.memFraction,
                '${load.memUsedMb} / ${load.memTotalMb} МБ'),
            const SizedBox(height: 8),
            _bar(_ru ? 'Диск' : 'Disk', load.diskFraction,
                '${load.diskUsedGb} / ${load.diskTotalGb} ГБ'),
            const SizedBox(height: 10),
            _row(
              _ru ? 'Аптайм' : 'Uptime',
              _ru
                  ? '${load.uptime.inDays} дн. ${load.uptime.inHours % 24} ч.'
                  : '${load.uptime.inDays}d ${load.uptime.inHours % 24}h',
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- мелочи

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );

  Widget _cardTitle(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary)),
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textPrimary)),
            ),
          ],
        ),
      );

  Widget _metric(String label, String value, {bool alarming = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color:
                      alarming ? AppTheme.accentRed : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bar(String label, double fraction, String detail) {
    final v = fraction.clamp(0.0, 1.0);
    final color = v >= 0.9
        ? AppTheme.accentRed
        : v >= 0.7
            ? AppTheme.accent
            : AppTheme.accentGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            Text('$detail · ${(v * 100).round()}%',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 6,
            backgroundColor: AppTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// График живого пинга с подписанной шкалой.
class _LiveChart extends CustomPainter {
  final ProbeStats stats;

  _LiveChart(this.stats);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppTheme.glassBorder
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final samples = stats.samples;
    if (samples.length < 2) return;

    // Верх шкалы — по максимуму с запасом, но не меньше 50 мс: иначе на
    // быстром канале шум в пару миллисекунд превращается в горы.
    final top = (stats.maxMs ?? 50) < 50 ? 50.0 : (stats.maxMs! * 1.15);
    final step = size.width / (samples.length - 1);

    final line = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = AppTheme.accent.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    final fail = Paint()
      ..color = AppTheme.accentRed.withOpacity(0.5)
      ..strokeWidth = 1.6;

    final path = Path();
    final area = Path();
    var started = false;

    for (var i = 0; i < samples.length; i++) {
      final x = i * step;
      final s = samples[i];
      if (!s.ok || s.ms == null) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), fail);
        if (started) {
          area.lineTo(x, size.height);
          canvas.drawPath(area, fill);
          area.reset();
        }
        started = false;
        continue;
      }
      final y = size.height - (s.ms! / top) * size.height;
      if (!started) {
        path.moveTo(x, y);
        area
          ..moveTo(x, size.height)
          ..lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    if (started) {
      area.lineTo((samples.length - 1) * step, size.height);
      canvas.drawPath(area, fill);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_LiveChart old) => true;
}
