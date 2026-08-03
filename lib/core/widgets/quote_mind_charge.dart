import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../localization/wesi_locale.dart';
import '../services/quote_mind_charge_service.dart';
import '../theme/app_theme.dart';

/// Компактный блок «заряд умных мыслей» — справа от часов на Home.
///
/// Текст-призыв + прогресс-бар (0…10 цитат). При достижении 10 —
/// короткий салют (цвет = AppTheme.accent) и поздравление.
/// При 40 — секретная надпись.
class QuoteMindCharge extends StatefulWidget {
  const QuoteMindCharge({super.key});

  @override
  State<QuoteMindCharge> createState() => _QuoteMindChargeState();
}

class _QuoteMindChargeState extends State<QuoteMindCharge>
    with TickerProviderStateMixin {
  late final AnimationController _burstCtrl;
  late final AnimationController _msgCtrl;
  String? _message;
  bool _secret = false;

  @override
  void initState() {
    super.initState();
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _msgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    QuoteMindChargeService.celebratePrimary.addListener(_onPrimary);
    QuoteMindChargeService.celebrateSecret.addListener(_onSecret);

    // Если уже достигли порогов раньше — сразу показываем состояние
    // (без повторного салюта).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (QuoteMindChargeService.reachedSecret) {
        _showMessage(secret: true, animate: false);
      } else if (QuoteMindChargeService.reachedPrimary) {
        _showMessage(secret: false, animate: false);
      }
    });
  }

  @override
  void dispose() {
    QuoteMindChargeService.celebratePrimary.removeListener(_onPrimary);
    QuoteMindChargeService.celebrateSecret.removeListener(_onSecret);
    _burstCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _onPrimary() {
    if (!mounted) return;
    _burstCtrl.forward(from: 0);
    _showMessage(secret: false, animate: true);
  }

  void _onSecret() {
    if (!mounted) return;
    _burstCtrl.forward(from: 0);
    _showMessage(secret: true, animate: true);
  }

  void _showMessage({required bool secret, required bool animate}) {
    setState(() {
      _secret = secret;
      _message = secret
          ? (WesiLocale.isRussian
              ? 'Тебя не остановить, заряд умных мыслей уже запасён на неделю вперед, пхех!'
              : 'Unstoppable — smart-thought charge stocked for a week ahead, heh!')
          : (WesiLocale.isRussian
              ? 'Молодец, заряд умных мыслей получен!'
              : 'Nice! Smart-thought charge unlocked!');
    });
    if (animate) {
      _msgCtrl.forward(from: 0);
    } else {
      _msgCtrl.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: QuoteMindChargeService.count,
          builder: (context, count, __) {
            final progress = QuoteMindChargeService.progress01;
            final accent = AppTheme.accent;
            final isRu = WesiLocale.isRussian;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 170, maxWidth: 230),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.glassBorder),
                    color: AppTheme.surface.withOpacity(0.55),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isRu
                            ? 'Зарядись умными мыслями'
                            : 'Charge up with smart thoughts',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 5,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppTheme.surfaceLight,
                            valueColor: AlwaysStoppedAnimation(accent),
                            minHeight: 5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${count.clamp(0, QuoteMindChargeService.goalPrimary)}'
                        '/${QuoteMindChargeService.goalPrimary}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 6),
                        FadeTransition(
                          opacity: _msgCtrl,
                          child: Text(
                            _message!,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: _secret ? accent : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Салют поверх — лёгкие «искры» из центра блока
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _burstCtrl,
                      builder: (context, _) {
                        if (_burstCtrl.value == 0 || _burstCtrl.value == 1) {
                          return const SizedBox.shrink();
                        }
                        return CustomPaint(
                          painter: _SparksPainter(
                            progress: _burstCtrl.value,
                            color: accent,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Простой радиальный «салют» из точек — без внешних пакетов.
class _SparksPainter extends CustomPainter {
  _SparksPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _n = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.max(size.width, size.height) * 0.85;
    final t = Curves.easeOut.transform(progress);
    final fade = (1.0 - progress).clamp(0.0, 1.0);

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _n; i++) {
      final angle = (i / _n) * math.pi * 2 + progress * 0.8;
      final r = maxR * t * (0.55 + (i % 3) * 0.15);
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      final s = (2.2 + (i % 4) * 0.7) * (1.0 - t * 0.35);
      paint.color = color.withOpacity(0.15 + 0.75 * fade);
      canvas.drawCircle(Offset(x, y), s, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparksPainter old) =>
      old.progress != progress || old.color != color;
}
