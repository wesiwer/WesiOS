import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/monitor_target.dart';
import 'models/probe_result.dart';
import 'services/monitor_service.dart';
import 'target_detail_screen.dart';
import 'widgets/health_dot.dart';
import 'widgets/target_editor_sheet.dart';

/// Системный администратор — состояние серверов, доменов и сайта.
///
/// **Что здесь измеряется по-настоящему, а что нет.** Всё, что видно на этом
/// экране без агента, приложение измеряет само: время ответа, разрешение
/// имени, срок сертификата, код ответа сайта. Загрузку процессора и памяти
/// чужой машины из сети узнать нельзя никак — её присылает агент,
/// установленный на самом сервере. Пока агента нет, эти цифры не
/// показываются вовсе, а не рисуются наугад.
class SysadminScreen extends StatefulWidget {
  const SysadminScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SysadminScreen()),
      );

  @override
  State<SysadminScreen> createState() => _SysadminScreenState();
}

class _SysadminScreenState extends State<SysadminScreen> {
  Timer? _sweep;
  bool _busy = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Раз в пятнадцать секунд по списку. Чаще незачем: на обзорном экране
    // нужен ответ «всё живо или нет», а не миллисекунды. Живой пинг — внутри
    // карточки узла, и он идёт, только пока карточка открыта.
    _sweep = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _sweep?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    await MonitorService.probeAll();
    for (final t in MonitorService.targets) {
      await MonitorService.refreshSlow(t);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _add() async {
    final created = await TargetEditorSheet.show(context);
    if (created != null && mounted) {
      await MonitorService.probe(created);
      await MonitorService.refreshSlow(created);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MonitorService.revision,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: MonitorService.tick,
        builder: (context, __, ___) {
          final targets = MonitorService.targets;
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(targets.length),
                  Expanded(
                    child: targets.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: AppTheme.accent,
                            backgroundColor: AppTheme.surface,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              itemCount: targets.length,
                              itemBuilder: (context, i) => _card(targets[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: _add,
              backgroundColor: AppTheme.accent,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _header(int count) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WesiTitle(
                    _ru ? 'Системный администратор' : 'System administrator',
                    size: 20),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? (_ru ? 'Узлы не добавлены' : 'No targets yet')
                      : (_ru ? 'Под наблюдением: $count' : 'Watching: $count'),
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            )
          else
            IconButton(
              tooltip: _ru ? 'Проверить сейчас' : 'Check now',
              icon: Icon(Icons.refresh, size: 20, color: AppTheme.textMuted),
              onPressed: _refresh,
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 44, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              _ru
                  ? 'Добавьте сервер, домен или сайт — и здесь появится их '
                      'состояние.\n\nВремя ответа, разрешение имени и срок '
                      'сертификата приложение измеряет само. Загрузку '
                      'процессора и памяти присылает агент, установленный на '
                      'сервере, — без него этих цифр не будет.'
                  : 'Add a server, a domain or a site and their state shows '
                      'up here.\n\nResponse time, name resolution and '
                      'certificate expiry are measured by the app itself. CPU '
                      'and memory come from an agent installed on the server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.55, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(MonitorTarget t) {
    final stats = MonitorService.statsOf(t.id);
    final tls = MonitorService.tlsOf(t.id);
    final load = MonitorService.loadOf(t.id);
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => TargetDetailScreen.open(context, t.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HealthDot(grade: stats.grade),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_ru ? t.labelRu() : t.labelEn()} · ${t.host}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _latency(stats),
                ],
              ),
              if (stats.total > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 26,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _Sparkline(stats),
                  ),
                ),
              ],
              if (tls != null && tls.expiringSoon(now)) ...[
                const SizedBox(height: 9),
                _warning(
                  tls.expired(now)
                      ? (_ru
                          ? 'Сертификат истёк'
                          : 'Certificate has expired')
                      : (_ru
                          ? 'Сертификат кончается через ${tls.daysLeft(now)} дн.'
                          : 'Certificate expires in ${tls.daysLeft(now)} days'),
                ),
              ],
              if (load != null && !load.isStale(now)) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _mini(_ru ? 'ЦП' : 'CPU', load.cpuFraction),
                    const SizedBox(width: 8),
                    _mini(_ru ? 'Память' : 'RAM', load.memFraction),
                    const SizedBox(width: 8),
                    _mini(_ru ? 'Диск' : 'Disk', load.diskFraction),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _latency(ProbeStats stats) {
    final last = stats.last;
    if (last == null) {
      return Text('—',
          style: TextStyle(fontSize: 13, color: AppTheme.textMuted));
    }
    if (!last.ok) {
      return Text(
        _ru ? 'нет ответа' : 'no answer',
        style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.accentRed),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${last.ms!.round()} ${_ru ? 'мс' : 'ms'}',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary),
        ),
        if (stats.avgMs != null)
          Text(
            '${_ru ? 'сред.' : 'avg'} ${stats.avgMs!.round()}',
            style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
          ),
      ],
    );
  }

  Widget _warning(String text) => Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 14, color: AppTheme.accentRed),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(fontSize: 11.5, color: AppTheme.accentRed)),
          ),
        ],
      );

  Widget _mini(String label, double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    final color = clamped >= 0.9
        ? AppTheme.accentRed
        : clamped >= 0.7
            ? AppTheme.accent
            : AppTheme.accentGreen;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              Text('${(clamped * 100).round()}%',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 4,
              backgroundColor: AppTheme.surfaceLight,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// График времени ответа за окно замеров.
///
/// Неудачные замеры рисуются красной чертой во всю высоту, а не разрывом:
/// разрыв в линии читается как «данных не было», хотя данные как раз были —
/// узел не ответил.
class _Sparkline extends CustomPainter {
  final ProbeStats stats;

  _Sparkline(this.stats);

  @override
  void paint(Canvas canvas, Size size) {
    final samples = stats.samples;
    if (samples.length < 2) return;

    final maxMs = stats.maxMs ?? 1;
    final scale = maxMs <= 0 ? 1.0 : maxMs;
    final step = size.width / (samples.length - 1);

    final line = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final fail = Paint()
      ..color = AppTheme.accentRed.withOpacity(0.55)
      ..strokeWidth = 1.4;

    final path = Path();
    var started = false;

    for (var i = 0; i < samples.length; i++) {
      final x = i * step;
      final s = samples[i];
      if (!s.ok || s.ms == null) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), fail);
        started = false;
        continue;
      }
      final y = size.height - (s.ms! / scale) * size.height * 0.9 - 1;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_Sparkline old) =>
      old.stats.samples.length != stats.samples.length ||
      old.stats.last != stats.last;
}
