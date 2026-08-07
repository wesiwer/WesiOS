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

/// Системный администратор: сначала выбираем узел, затем работаем с ним.
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
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => const _MonitorOverview(),
    );
  }
}

class _MonitorOverview extends StatefulWidget {
  const _MonitorOverview();

  @override
  State<_MonitorOverview> createState() => _MonitorOverviewState();
}

class _MonitorOverviewState extends State<_MonitorOverview> {
  Timer? _sweep;
  bool _busy = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _refresh();
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
    for (final target in MonitorService.targets) {
      await MonitorService.refreshSlow(target);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _add() async {
    final created = await TargetEditorSheet.show(context);
    if (created == null || !mounted) return;
    await MonitorService.probe(created);
    await MonitorService.refreshSlow(created);
    if (mounted) setState(() {});
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
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(_ru ? 'Узел' : 'Target'),
            ),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(targets),
                  _healthStrip(targets),
                  Expanded(
                    child: targets.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: AppTheme.accent,
                            backgroundColor: AppTheme.surface,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: targets.length,
                              itemBuilder: (_, index) => _card(targets[index]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(List<MonitorTarget> targets) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: AppTheme.accent.withOpacity(.12),
              border: Border.all(color: AppTheme.accent.withOpacity(.25)),
            ),
            child: Icon(Icons.dns_outlined, color: AppTheme.accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WesiTitle(
                    _ru ? 'Системный администратор' : 'System administrator',
                    size: 19),
                const SizedBox(height: 2),
                Text(
                  targets.isEmpty
                      ? (_ru ? 'Узлы не добавлены' : 'No targets yet')
                      : (_ru
                          ? '${targets.length} узлов · обновление каждые 15 секунд'
                          : '${targets.length} targets · refresh every 15 seconds'),
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            )
          else
            IconButton(
              tooltip: _ru ? 'Проверить сейчас' : 'Check now',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }

  Widget _healthStrip(List<MonitorTarget> targets) {
    final grades = [
      for (final target in targets) MonitorService.statsOf(target.id).grade
    ];
    final good = grades.where((value) => value == HealthGrade.good).length;
    final bad = grades
        .where((value) =>
            value == HealthGrade.down || value == HealthGrade.degraded)
        .length;
    final unknown = grades
        .where((value) =>
            value == HealthGrade.unknown || value == HealthGrade.offline)
        .length;
    return SizedBox(
      height: 72,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        children: [
          _healthMetric(Icons.check_circle_outline,
              _ru ? 'Работают' : 'Healthy', '$good', AppTheme.accentGreen),
          const SizedBox(width: 8),
          _healthMetric(Icons.warning_amber_rounded,
              _ru ? 'Проблемы' : 'Issues', '$bad', AppTheme.accentRed),
          const SizedBox(width: 8),
          _healthMetric(Icons.help_outline, _ru ? 'Нет данных' : 'Unknown',
              '$unknown', AppTheme.textMuted),
        ],
      ),
    );
  }

  Widget _healthMetric(
          IconData icon, String label, String value, Color color) =>
      Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.surface.withOpacity(.48),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 9),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary)),
                Text(label,
                    style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              ],
            ),
          ],
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined, size: 46, color: AppTheme.textMuted),
              const SizedBox(height: 14),
              Text(
                _ru
                    ? 'Добавьте сервер, домен или сайт. WesiOS измерит отклик, DNS, HTTP и срок TLS-сертификата.'
                    : 'Add a server, domain, or site. WesiOS will measure latency, DNS, HTTP, and TLS expiry.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _card(MonitorTarget target) {
    final stats = MonitorService.statsOf(target.id);
    final tls = MonitorService.tlsOf(target.id);
    final load = MonitorService.loadOf(target.id);
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => TargetDetailScreen.open(context, target.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(.47),
              borderRadius: BorderRadius.circular(16),
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
                          Text(target.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            '${_ru ? target.labelRu() : target.labelEn()} · ${target.host}:${target.port}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _latency(stats),
                  ],
                ),
                if (stats.total > 1) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 28,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _Sparkline(stats),
                    ),
                  ),
                ],
                if (tls != null && tls.expiringSoon(now)) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: AppTheme.accentRed),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          tls.expired(now)
                              ? (_ru
                                  ? 'Сертификат истёк'
                                  : 'Certificate expired')
                              : (_ru
                                  ? 'Сертификат истекает через ${tls.daysLeft(now)} дн.'
                                  : 'Certificate expires in ${tls.daysLeft(now)} days'),
                          style: TextStyle(
                              fontSize: 10.5, color: AppTheme.accentRed),
                        ),
                      ),
                    ],
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
      ),
    );
  }

  Widget _latency(ProbeStats stats) {
    final last = stats.last;
    if (last == null) {
      return Text('—', style: TextStyle(color: AppTheme.textMuted));
    }
    if (!last.ok) {
      return Text(
        _ru ? 'нет ответа' : 'no answer',
        style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentRed),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${last.ms!.round()} ms',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppTheme.textPrimary)),
        if (stats.avgMs != null)
          Text('${_ru ? 'сред.' : 'avg'} ${stats.avgMs!.round()}',
              style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
      ],
    );
  }

  Widget _mini(String label, double fraction) {
    final value = fraction.clamp(0.0, 1.0);
    final color = value >= .9
        ? AppTheme.accentRed
        : value >= .7
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
                  style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              Text('${(value * 100).round()}%',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
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
      ..color = AppTheme.accentRed.withOpacity(.55)
      ..strokeWidth = 1.3;
    final path = Path();
    var started = false;
    for (var index = 0; index < samples.length; index++) {
      final x = index * step;
      final sample = samples[index];
      if (!sample.ok || sample.ms == null) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), fail);
        started = false;
        continue;
      }
      final y = size.height - (sample.ms! / scale) * size.height * .9 - 1;
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
  bool shouldRepaint(_Sparkline oldDelegate) =>
      oldDelegate.stats.samples.length != stats.samples.length ||
      oldDelegate.stats.last != stats.last;
}
