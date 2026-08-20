import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Telegram-style paper plane used by WesiOS.
///
/// Material's Telegram/send glyphs can render horizontally depending on the
/// platform/font version. Telegram's mark points to the upper-right, so keep
/// the orientation explicit instead of relying on the platform glyph.
class WesiTelegramIcon extends StatelessWidget {
  const WesiTelegramIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -math.pi / 4,
      child: Icon(
        Icons.send_rounded,
        size: size,
        color: color,
        semanticLabel: 'Telegram',
      ),
    );
  }
}
