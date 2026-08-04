import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'models/employee_model.dart';
import 'services/team_service.dart';

/// Показатели людей.
///
/// Кто что видит:
/// - без права `canSeeOthersStats` — только свои цифры;
/// - с правом — цифры всех.
///
/// Проверка стоит на входе, а не рисует чужие строки серым: строка, которую
/// видно, но нельзя прочитать, всё равно выдаёт и число сотрудников, и их
/// имена.
///
/// Цифры пока проверочные — они создаются вместе с сотрудником и помечены на
/// экране. Настоящие появятся с сервером; форма экрана от этого не изменится,
/// поменяется источник.
class TeamStatsScreen extends StatefulWidget {
  const TeamStatsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TeamStatsScreen()),
      );

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen> {
  bool get _ru => WesiLocale.isRussian;

  List<EmployeeModel> get _people {
    final p = TeamService.currentPermissions;
    if (p.canSeeOthersStats) return TeamService.all;
    final me = TeamService.current;
    return me == null ? TeamService.all : [me];
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final everyone = TeamService.currentPermissions.canSeeOthersStats;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
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
                            _ru ? 'Показатели' : 'Performance', size: 22),
                        const SizedBox(height: 2),
                        Text(
                          everyone
                              ? (_ru ? 'По всем людям' : 'Everyone')
                              : (_ru ? 'Только ваши' : 'Yours only'),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.science_outlined,
                        size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _ru
                            ? 'Цифры проверочные — они выдаются при создании '
                                'человека, чтобы можно было пройти путь '
                                'целиком. Настоящие приедут с сервером.'
                            : 'The numbers are placeholders issued when a '
                                'person is created. Real ones arrive with the '
                                'server.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: people.length,
                itemBuilder: (context, i) => _card(people[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(EmployeeModel e) {
    final s = e.demoStats;
    final efficiency = s['efficiency'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                WesiAvatar(size: 36, index: e.avatarIndex),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.displayName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      if (e.position.isNotEmpty)
                        Text(e.position,
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            if (s.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _ru ? 'Данных пока нет' : 'No data yet',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _metric(_ru ? 'Баланс' : 'Balance',
                      CurrencyService.format(s['balance'] ?? 0)),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'Доход/мес' : 'Income',
                      CurrencyService.format(s['incomeMonth'] ?? 0)),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'Расход/мес' : 'Expense',
                      CurrencyService.format(s['expenseMonth'] ?? 0)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _metric(_ru ? 'Задач готово' : 'Done',
                      '${(s['tasksDone'] ?? 0).toInt()}'),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'В работе' : 'Open',
                      '${(s['tasksOpen'] ?? 0).toInt()}'),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'Эффективность' : 'Efficiency',
                      '${(efficiency * 100).toStringAsFixed(0)}%'),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: efficiency.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(
                    efficiency >= 0.75
                        ? AppTheme.accentGreen
                        : efficiency >= 0.5
                            ? AppTheme.accent
                            : AppTheme.accentRed,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              const SizedBox(height: 3),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ],
          ),
        ),
      );
}
