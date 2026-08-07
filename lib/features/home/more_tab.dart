import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../team/models/team_permissions.dart';
import '../team/services/team_service.dart';

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
            module: TeamModules.tasks,
            icon: Icons.task_alt,
            title: ru ? 'Задачи' : 'Tasks',
            subtitle: ru
                ? 'Канбан, сроки, исполнители'
                : 'Kanban, deadlines, assignees',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/roadmap',
            module: TeamModules.roadmap,
            icon: Icons.timeline,
            title: 'Roadmap',
            subtitle: ru
                ? 'Проекты, этапы, вехи, зависимости и диаграмма Ганта'
                : 'Projects, phases, milestones, dependencies, and Gantt',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/calendar',
            module: TeamModules.calendar,
            icon: Icons.calendar_month,
            title: ru ? 'Календарь' : 'Calendar',
            subtitle: ru
                ? 'Сетка месяца работает, события — впереди'
                : 'Month grid works, events are next',
            stage: ModuleStage.partial,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Знания и клиенты' : 'Knowledge & clients',
        items: [
          _ModuleItem(
            route: '/knowledge',
            module: TeamModules.knowledge,
            icon: Icons.menu_book,
            title: ru ? 'База знаний' : 'Knowledge Base',
            subtitle: ru
                ? 'Регламенты, инструкции и раздел «О программе»'
                : 'Playbooks, guides and the About section',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/contacts',
            module: TeamModules.contacts,
            icon: Icons.contacts,
            title: ru ? 'Контакты' : 'Contacts',
            subtitle: ru
                ? 'Сотрудники, связь, доступы'
                : 'Employees, contacts, access',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/chats',
            module: TeamModules.chats,
            icon: Icons.forum_outlined,
            title: ru ? 'Чаты' : 'Chats',
            subtitle: ru
                ? 'Группы, темы, архив. Доставка другим — с сервером'
                : 'Groups, topics, archive. Delivery awaits the server',
            stage: ModuleStage.partial,
          ),
          _ModuleItem(
            route: '/crm',
            module: TeamModules.crm,
            icon: Icons.people_alt,
            title: 'CRM',
            subtitle: ru
                ? 'Клиенты, воронка сделок, касания и напоминания'
                : 'Clients, deal pipeline, interactions, and follow-ups',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/ai',
            module: TeamModules.ai,
            icon: Icons.auto_awesome,
            title: 'Wesi AI',
            subtitle: ru
                ? 'Ассистент по вашим данным'
                : 'Assistant over your own data',
            stage: ModuleStage.planned,
          ),
        ],
      ),
      _Section(
        title: ru ? 'Финансы' : 'Finance',
        items: [
          _ModuleItem(
            route: '/treasury',
            module: TeamModules.treasury,
            icon: Icons.account_balance_wallet,
            title: 'Wesi Treasury',
            subtitle:
                ru ? 'Доходы, траты, операции' : 'Income, expenses, operations',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/treasury/forecast',
            module: TeamModules.forecast,
            icon: Icons.query_stats,
            title: ru ? 'Прогноз' : 'Forecast',
            subtitle: ru
                ? 'Monte-Carlo, Cash Gap, «Что если?»'
                : 'Monte-Carlo, Cash Gap, What-If',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/treasury/sandbox',
            module: TeamModules.sandbox,
            icon: Icons.science,
            title: ru ? 'Песочница' : 'Sandbox',
            subtitle: ru ? 'Изолированные сценарии' : 'Isolated scenarios',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/analytics',
            module: TeamModules.analytics,
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
            module: TeamModules.audio,
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
            module: TeamModules.shield,
            icon: Icons.shield_outlined,
            title: 'Wesi Shield',
            subtitle: ru
                ? 'Пароль, биометрия, автоблокировка, журнал'
                : 'Password, biometrics, auto-lock, log',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/sysadmin',
            module: TeamModules.sysadmin,
            icon: Icons.dns_outlined,
            title: ru ? 'Системный администратор' : 'System administrator',
            subtitle: ru
                ? 'Выберите сервер: мониторинг, TLS, нагрузка и консоль'
                : 'Choose a server: monitoring, TLS, load, and console',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/keys',
            module: TeamModules.keys,
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
            subtitle: ru
                ? 'Язык, модели прогноза, данные'
                : 'Language, forecast models, data',
            stage: ModuleStage.ready,
          ),
          _ModuleItem(
            route: '/profile',
            icon: Icons.person,
            title: ru ? 'Профиль' : 'Profile',
            subtitle:
                ru ? 'Аватар и ключи Firebase' : 'Avatar and Firebase keys',
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

    final visibleSections = sections
        .map((section) => _Section(
              title: section.title,
              items: section.items
                  .where((item) =>
                      item.module == null ||
                      TeamService.currentPermissions.allows(item.module!))
                  .toList(),
            ))
        .where((section) => section.items.isNotEmpty);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 16, 16, 32),
        children: [
          WesiTitle(ru ? 'Ещё' : 'More'),
          const SizedBox(height: 4),
          Text(
            ru
                ? 'Все модули WesiOS. Пометка показывает их реальную готовность.'
                : 'Every WesiOS module. Each badge reflects its real readiness.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          for (final section in visibleSections) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                section.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            for (final item in section.items) _tile(context, item, ru),
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
              color: AppTheme.surface.withOpacity(.4),
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
                    color: item.stage.color.withOpacity(.12),
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
                              style: TextStyle(
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
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 13, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(ModuleStage stage, bool ru) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: stage.color.withOpacity(.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: stage.color.withOpacity(.35)),
        ),
        child: Text(
          ru ? stage.labelRu : stage.labelEn,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: stage.color),
        ),
      );
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
  final String? module;

  const _ModuleItem({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.stage,
    this.module,
  });
}
