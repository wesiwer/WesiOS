import 'package:flutter/material.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/widgets/module_scaffold.dart';

/// Вкладка «Ещё» — витрина всех модулей WesiOS.
///
/// Раньше здесь сразу открывались Настройки, из-за чего остальные разделы
/// (база знаний, CRM, ИИ, аудио, roadmap) были не видны вообще — о них можно
/// было узнать только из кода. Теперь это карта продукта: видно и что уже
/// работает, и что задумано, с честной пометкой стадии у каждого модуля.
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    final sections = <_Section>[
      _Section(
        title: ru ? 'Работа' : 'Work',
        items: [
          _ModuleItem(
            route: '/tasks',
            icon: Icons.task_alt,
            title: ru ? 'Задачи' : 'Tasks',
            subtitle: ru ? 'Канбан, сроки, исполнители' : 'Kanban, deadlines, assignees',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/roadmap',
            icon: Icons.timeline,
            title: 'Roadmap',
            subtitle: ru ? 'Проекты во времени, диаграмма Ганта' : 'Projects over time, Gantt chart',
            stage: ModuleStage.planned,
          ),
          _ModuleItem(
            route: '/calendar',
            icon: Icons.calendar_month,
            title: ru ? 'Календарь' : 'Calendar',
            subtitle: ru ? 'Сетка месяца работает, события — впереди' : 'Month grid works, events are next',
            stage: ModuleStage.partial,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Знания и клиенты' : 'Knowledge & clients',
        items: [
          _ModuleItem(
            route: '/knowledge',
            icon: Icons.menu_book,
            title: ru ? 'База знаний' : 'Knowledge Base',
            subtitle: ru
                ? 'Регламенты, инструкции и раздел «О программе»'
                : 'Playbooks, guides and the About section',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/crm',
            icon: Icons.people_alt,
            title: 'CRM',
            subtitle: ru ? 'Клиенты, сделки, история' : 'Clients, deals, history',
            stage: ModuleStage.planned,
          ),
          _ModuleItem(
            route: '/ai',
            icon: Icons.auto_awesome,
            title: 'Wesi AI',
            subtitle: ru ? 'Ассистент по вашим данным' : 'Assistant over your own data',
            stage: ModuleStage.planned,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Финансы' : 'Finance',
        items: [
          _ModuleItem(
            route: '/treasury',
            icon: Icons.account_balance_wallet,
            title: 'Wesi Treasury',
            subtitle: ru ? 'Доходы, траты, операции' : 'Income, expenses, operations',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/treasury/forecast',
            icon: Icons.query_stats,
            title: ru ? 'Прогноз' : 'Forecast',
            subtitle: ru
                ? 'Monte-Carlo, Cash Gap, «Что если?»'
                : 'Monte-Carlo, Cash Gap, What-If',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/treasury/sandbox',
            icon: Icons.science,
            title: ru ? 'Песочница' : 'Sandbox',
            subtitle: ru ? 'Изолированные сценарии' : 'Isolated scenarios',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/analytics',
            icon: Icons.analytics,
            title: ru ? 'Аналитика' : 'Analytics',
            subtitle: ru
                ? 'KPI, динамика, здоровье бизнеса'
                : 'KPIs, trends, business health',
            stage: ModuleStage.ready,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Творчество' : 'Creative',
        items: [
          _ModuleItem(
            route: '/audio',
            icon: Icons.graphic_eq,
            title: 'Audio Vault',
            subtitle: ru ? 'Биты, демо, лицензии' : 'Beats, demos, licences',
            stage: ModuleStage.planned,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Система' : 'System',
        items: [
          _ModuleItem(
            route: '/shield',
            icon: Icons.shield_outlined,
            title: 'Wesi Shield',
            subtitle: ru
                ? 'Пароль, биометрия, автоблокировка, журнал'
                : 'Password, biometrics, auto-lock, log',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/keys',
            icon: Icons.vpn_key_outlined,
            title: ru ? 'Ключи' : 'Keys',
            subtitle: ru
                ? 'Ключи сервисов: Shield, вход и правила Firestore'
                : 'Service keys: Shield, sign-in and Firestore rules',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/settings',
            icon: Icons.settings,
            title: ru ? 'Настройки' : 'Settings',
            subtitle: ru ? 'Язык, модели прогноза, данные' : 'Language, forecast models, data',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/profile',
            icon: Icons.person,
            title: ru ? 'Профиль' : 'Profile',
            subtitle: ru ? 'Аватар и ключи Firebase' : 'Avatar and Firebase keys',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/founder',
            icon: Icons.auto_stories,
            title: ru ? 'История основателя' : 'Founder story',
            subtitle: ru ? 'Зачем всё это' : 'Why any of this exists',
            stage: ModuleStage.ready,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 16, 16, 32),
        children: [
          WesiTitle(ru ? 'Ещё' : 'More'),
          const SizedBox(height: 4),
          Text(
            ru
                ? 'Все модули WesiOS. Пометка у каждого показывает, что уже работает, а что пока макет.'
                : 'Every WesiOS module. The badge on each shows what already works and what is still a mock-up.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                section.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            ...section.items.map((item) => _tile(context, item, ru)),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, _ModuleItem item, bool ru) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pushNamed(context, item.route),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: item.stage.color.withOpacity(0.12),
                  ),
                  child: Icon(item.icon, size: 19, color: item.stage.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _badge(item.stage, ru),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 13, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(ModuleStage stage, bool ru) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: stage.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stage.color.withOpacity(0.35)),
      ),
      child: Text(
        ru ? stage.labelRu : stage.labelEn,
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: stage.color),
      ),
    );
  }
}

class _Section {
  final String title;
  final List<_ModuleItem> items;
  const _Section({required this.title, required this.items});
}

class _ModuleItem {
  final String route;
  final IconData icon;
  final String title;
  final String subtitle;
  final ModuleStage stage;

  const _ModuleItem({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.stage,
  });
}
