import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/audio_vault_models.dart';

class LeaseCountdown extends StatefulWidget {
  final BeatLease lease;
  final bool compact;
  const LeaseCountdown({super.key, required this.lease, this.compact = false});

  @override
  State<LeaseCountdown> createState() => _LeaseCountdownState();
}

class _LeaseCountdownState extends State<LeaseCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.lease.endsAt.difference(DateTime.now());
    final expired = diff.isNegative;
    final abs = diff.abs();
    final days = abs.inDays;
    final hours = abs.inHours.remainder(24);
    final mins = abs.inMinutes.remainder(60);
    final text = expired
        ? (days > 0 ? 'Истекло $days д. $hours ч. назад' : 'Истекло $hours ч. $mins мин. назад')
        : (days > 0 ? 'Осталось $days д. $hours ч.' : 'Осталось $hours ч. $mins мин.');
    final color = expired
        ? AppTheme.accentRed
        : diff.inDays <= 3
            ? Colors.orange
            : AppTheme.accentGreen;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 7 : 10,
        vertical: widget.compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined,
              size: widget.compact ? 12 : 15, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: widget.compact ? 9 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
