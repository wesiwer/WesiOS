import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../localization/wesi_locale.dart';
import '../services/quote_mind_charge_service.dart';
import '../theme/app_theme.dart';

/// Блок «заряд умных мыслей».
///
/// [expanded] делает его той же ширины, что и карточка цитаты. На главной это
/// основной вариант: два связанных блока должны выглядеть одной системой, а
/// не маленьким индикатором, случайно прижатым к иконкам профиля.
class QuoteMindCharge extends StatefulWidget {
  final bool expanded;

  const QuoteMindCharge({super.key, this.expanded = false});

  @override
  State<QuoteMindCharge> createState() => _QuoteMindChargeState();
}

class _QuoteMindChargeState extends State<QuoteMindCharge>
    with TickerProviderStateMixin {
  late final AnimationController _burstCtrl;
  late final AnimationController _msgCtrl;
  bool _showMessage = false;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (QuoteMindChargeService.reachedSecret) {
        _show(secret: true, animate: false);
      } else if (QuoteMindChargeService.reachedPrimary) {
        _show(secret: false, animate: false);
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
    _show(secret: false, animate: true);
  }

  void _onSecret() {
    if (!mounted) return;
    _burstCtrl.forward(from: 0);
    _show(secret: true, animate: true);
  }

  void _show({required bool secret, required bool animate}) {
    setState(() {
      _secret = secret;
      _showMessage = true;
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
        return ValueListenableBuilder<String>(
          valueListenable: WesiLocale.localeNotifier,
          builder: (context, _, __) {
            return ValueListenableBuilder<int>(
              valueListenable: QuoteMindChargeService.count,
              builder: (context, count, __) {
                final progress = QuoteMindChargeService.progress01;
                final accent = AppTheme.accent;
                final isRu = WesiLocale.isRussian;
                final message = _secret
                    ? (isRu
                        ? 'Тебя не остановить — запас умных мыслей уже на неделю вперёд.'
                        : 'Unstoppable — smart thoughts are stocked for a week.')
                    : (isRu
                        ? 'Молодец, заряд умных мыслей получен!'
                        : 'Nice! Smart-thought charge unlocked!');

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: widget.expanded ? double.infinity : null,
                      constraints: widget.expanded
                          ? const BoxConstraints(minHeight: 86)
                          : const BoxConstraints(
                              minWidth: 170,
                              maxWidth: 230,
                            ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.glassBorder),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.accent.withOpacity(0.08),
                            AppTheme.surface.withOpacity(0.46),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 17,
                                color: accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isRu
                                      ? 'Зарядись умными мыслями'
                                      : 'Charge up with smart thoughts',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${count.clamp(0, QuoteMindChargeService.goalPrimary)}'
                                '/${QuoteMindChargeService.goalPrimary}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: SizedBox(
                              height: 6,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: AppTheme.surfaceLight,
                                valueColor: AlwaysStoppedAnimation(accent),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          if (_showMessage) ...[
                            const SizedBox(height: 8),
                            FadeTransition(
                              opacity: _msgCtrl,
                              child: Text(
                                message,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: _secret
                                      ? accent
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _burstCtrl,
                          builder: (context, _) {
                            if (_burstCtrl.value == 0 ||
                                _burstCtrl.value == 1) {
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
      },
    );
  }
}

class _SparksPainter extends CustomPainter {
  _SparksPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const int _count = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height) * 0.85;
    final t = Curves.easeOut.transform(progress);
    final fade = (1.0 - progress).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * math.pi * 2 + progress * 1.2;
      final radius = maxRadius * t * (0.55 + 0.45 * ((i % 3) / 2));
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      paint.color = color.withOpacity(0.85 * fade);
      canvas.drawCircle(point, 2.2 * (1.0 - t * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparksPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
