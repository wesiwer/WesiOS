import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(GatewayTokens.space16),
    this.onTap,
    this.radius = GatewayTokens.radiusLarge,
    this.blur = 18,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final double blur;
  final Color? color;

  static final Map<double, ImageFilter> _blurFilters = <double, ImageFilter>{};

  static ImageFilter _blurFilter(double sigma) {
    return _blurFilters.putIfAbsent(
      sigma,
      () => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderRadius = BorderRadius.circular(radius);
    // Metric cards historically requested sigma 12 while the rest of the
    // dashboard used sigma 18. A single grouped backdrop filter is much cheaper
    // for the GPU when all dashboard glass shares the same filter. Promote the
    // lighter variant instead of reducing any effect: visually the small cards
    // become slightly richer while the renderer can reuse the sigma-18 pass.
    final effectiveBlur = blur == 12 ? 18.0 : blur;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter.grouped(
        filter: _blurFilter(effectiveBlur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? palette.glass,
            borderRadius: borderRadius,
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.06,
                ),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: RepaintBoundary(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: GatewayTokens.space4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
