import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';

/// Компактный календарь текущего месяца рядом с часами на главной.
///
/// Это не второй полноценный календарь: нажатие открывает существующий экран,
/// а сам виджет даёт быстрый визуальный ориентир — месяц, дни недели и сегодня.
class HomeMonthCalendar extends StatelessWidget {
  final DateTime? now;

  const HomeMonthCalendar({super.key, this.now});

  static const _monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final current = now ?? DateTime.now();
    final ru = WesiLocale.isRussian;
    final first = DateTime(current.year, current.month, 1);
    final days = DateTime(current.year, current.month + 1, 0).day;
    final leading = first.weekday - 1;
    final compact = MediaQuery.sizeOf(context).width < 390;

    return Semantics(
      button: true,
      label: ru ? 'Открыть календарь' : 'Open calendar',
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/calendar'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: compact ? 122 : 142,
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 10,
            compact ? 8 : 9,
            compact ? 8 : 10,
            compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.52),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (ru ? _monthsRu : _monthsEn)[current.month - 1],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 10.5 : 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${current.year}',
                    style: TextStyle(
                      fontSize: compact ? 8 : 9,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final label in (ru
                      ? const ['П', 'В', 'С', 'Ч', 'П', 'С', 'В']
                      : const ['M', 'T', 'W', 'T', 'F', 'S', 'S']))
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: compact ? 7 : 7.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.12,
                ),
                itemCount: 42,
                itemBuilder: (context, index) {
                  final day = index - leading + 1;
                  final valid = day >= 1 && day <= days;
                  final today = valid && day == current.day;
                  return Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: compact ? 14 : 16,
                      height: compact ? 14 : 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: today
                            ? AppTheme.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: today
                            ? [
                                BoxShadow(
                                  color: AppTheme.accent.withOpacity(0.28),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        valid ? '$day' : '',
                        style: TextStyle(
                          fontSize: compact ? 7.5 : 8,
                          height: 1,
                          fontWeight:
                              today ? FontWeight.w800 : FontWeight.w500,
                          color: today
                              ? Colors.white
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
