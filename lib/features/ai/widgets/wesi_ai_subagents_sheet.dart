import 'package:flutter/material.dart';

import '../models/wesi_ai_chat_models.dart';
import '../wesi_ai_managed_controller.dart';

class WesiAiSubagentsSheet extends StatefulWidget {
  final WesiAiManagedChatController controller;

  const WesiAiSubagentsSheet({
    super.key,
    required this.controller,
  });

  @override
  State<WesiAiSubagentsSheet> createState() => _WesiAiSubagentsSheetState();
}

class _WesiAiSubagentsSheetState extends State<WesiAiSubagentsSheet> {
  static const _agents = <_SubagentDefinition>[
    _SubagentDefinition(
      name: 'Coding / Flutter Agent',
      description: 'Код, Flutter, архитектура и точечная реализация.',
      icon: Icons.code_rounded,
    ),
    _SubagentDefinition(
      name: 'QA Agent',
      description: 'Тесты, регрессии, edge cases и воспроизведение ошибок.',
      icon: Icons.fact_check_outlined,
    ),
    _SubagentDefinition(
      name: 'Build Agent',
      description: 'CI/CD, сборки, зависимости и релизные проблемы.',
      icon: Icons.build_circle_outlined,
    ),
    _SubagentDefinition(
      name: 'Research Agent',
      description: 'Исследование вариантов, документации и фактов.',
      icon: Icons.manage_search_rounded,
    ),
    _SubagentDefinition(
      name: 'Documents Agent',
      description: 'Документы, спецификации, отчёты и структурирование.',
      icon: Icons.description_outlined,
    ),
    _SubagentDefinition(
      name: 'Media Agent',
      description: 'Медиа-задачи, ассеты и анализ материалов.',
      icon: Icons.perm_media_outlined,
    ),
    _SubagentDefinition(
      name: 'Review Agent',
      description: 'Независимая проверка решения и поиск слабых мест.',
      icon: Icons.rate_review_outlined,
    ),
    _SubagentDefinition(
      name: 'Security Reviewer',
      description: 'Авторизация, секреты, права и security-регрессии.',
      icon: Icons.security_outlined,
    ),
  ];

  static const _agencyDivisions = <_AgencyDivision>[
    _AgencyDivision('Engineering', 'Разработка, backend, frontend, AI, data, DevOps и архитектура.', Icons.code_rounded),
    _AgencyDivision('Testing', 'QA, API-тестирование, регрессии и quality engineering.', Icons.science_outlined),
    _AgencyDivision('Security', 'Threat modeling, AppSec, auth, privacy и security review.', Icons.shield_outlined),
    _AgencyDivision('Product', 'Продуктовая стратегия, discovery, roadmap и feature planning.', Icons.inventory_2_outlined),
    _AgencyDivision('Project Management', 'Delivery, планирование, процессы, сроки и координация.', Icons.assignment_outlined),
    _AgencyDivision('Design', 'UI, UX, визуальная система, бренд и creative direction.', Icons.palette_outlined),
    _AgencyDivision('Marketing', 'Growth, content, social, lifecycle и маркетинговая стратегия.', Icons.campaign_outlined),
    _AgencyDivision('Paid Media', 'Реклама, performance campaigns и paid acquisition.', Icons.touch_app_outlined),
    _AgencyDivision('Finance', 'Финансовый анализ, модели, бюджетирование и прогнозы.', Icons.account_balance_outlined),
    _AgencyDivision('Sales', 'Продажи, лиды, сделки, revenue-процессы и enablement.', Icons.trending_up_rounded),
    _AgencyDivision('Support', 'Customer support, service operations и клиентский опыт.', Icons.support_agent_outlined),
    _AgencyDivision('Academic', 'Исследования, статистика, история и академический анализ.', Icons.school_outlined),
    _AgencyDivision('GIS', 'Карты, геоданные, spatial analysis и GIS engineering.', Icons.map_outlined),
    _AgencyDivision('Healthcare', 'Медицинские и healthcare-домены для профильного анализа.', Icons.health_and_safety_outlined),
    _AgencyDivision('Game Development', 'Игровая разработка, игровые системы и production.', Icons.sports_esports_outlined),
    _AgencyDivision('Spatial Computing', 'XR/VR/AR, immersive interfaces и spatial experiences.', Icons.view_in_ar_outlined),
    _AgencyDivision('Specialized', 'Узкие роли: документы, отчёты, automation, orchestration и другое.', Icons.auto_awesome_outlined),
  ];

  WesiAiManagedChatController get controller => widget.controller;

  bool get _tierSupportsSubagents => controller.state.tier != WesiAiTier.fast;

  bool get _directPersonaSelected {
    final persona = controller.state.activeConversation?.persona;
    return persona == WesiAiPersona.zane || persona == WesiAiPersona.nirvana;
  }

  String? get _unavailableReason {
    if (!_tierSupportsSubagents) {
      return 'Субагенты доступны в Pro и Maximum. Переключите уровень в верхней панели.';
    }
    if (controller.state.activeConversation == null) {
      return 'Сначала откройте чат с Зейном или Нирваной.';
    }
    if (!_directPersonaSelected) {
      return 'Для ручного вызова откройте прямой чат с Зейном или Нирваной. В Lobby ведущая персона выбирается автоматически.';
    }
    return null;
  }

  Future<String?> _askTask(String title, {String? hint}) async {
    final taskController = TextEditingController();
    final task = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: taskController,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: hint ?? 'Что именно нужно проверить или сделать?',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = taskController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Позвать'),
          ),
        ],
      ),
    );
    taskController.dispose();
    return task;
  }

  Future<void> _submit(String prompt) async {
    final result = await controller.submitUserMessage(
      prompt,
      thinkingMode: true,
    );
    if (!mounted) return;
    if (result == WesiAiMessageSubmitResult.accepted) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_submitError(result))),
    );
  }

  Future<void> _invoke(_SubagentDefinition agent) async {
    if (_unavailableReason != null) return;
    final task = await _askTask('Задача для ${agent.name}');
    if (task == null || !mounted) return;
    await _submit('Позови субагента «${agent.name}» и поручи ему: $task');
  }

  Future<void> _invokeAgency(_AgencyDivision? division) async {
    if (_unavailableReason != null) return;
    final scope = division?.name ?? 'всего каталога';
    final task = await _askTask(
      division == null ? 'Автоподбор The Agency' : 'The Agency · ${division.name}',
      hint: division == null
          ? 'Опишите задачу — Wesi AI сам выберет узкого специалиста.'
          : 'Опишите задачу для специалиста из отдела $scope.',
    );
    if (task == null || !mounted) return;
    final divisionInstruction = division == null
        ? 'из всего каталога The Agency'
        : 'из отдела «${division.name}» каталога The Agency';
    await _submit(
      'Подбери наиболее подходящего специализированного субагента $divisionInstruction и поручи ему: $task',
    );
  }

  String _submitError(WesiAiMessageSubmitResult result) => switch (result) {
        WesiAiMessageSubmitResult.queueFull => 'Очередь Wesi AI заполнена.',
        WesiAiMessageSubmitResult.failed => 'Не удалось отправить задачу.',
        WesiAiMessageSubmitResult.accepted => '',
      };

  @override
  Widget build(BuildContext context) {
    final unavailable = _unavailableReason;
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Субагенты',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (unavailable != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(unavailable),
                ),
              ),
            const TabBar(
              tabs: [
                Tab(text: 'Базовые'),
                Tab(text: 'The Agency'),
              ],
            ),
            Flexible(
              child: TabBarView(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: _agents.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final agent = _agents[index];
                      return ListTile(
                        enabled: unavailable == null,
                        leading: Icon(agent.icon),
                        title: Text(agent.name),
                        subtitle: Text(agent.description),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: unavailable == null ? () => _invoke(agent) : null,
                      );
                    },
                  ),
                  ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    children: [
                      ListTile(
                        enabled: unavailable == null,
                        leading: const Icon(Icons.auto_awesome_rounded),
                        title: const Text('Автоподбор специалиста'),
                        subtitle: const Text('Wesi AI выберет наиболее подходящего агента из всего каталога The Agency.'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: unavailable == null ? () => _invokeAgency(null) : null,
                      ),
                      const Divider(height: 1),
                      ..._agencyDivisions.map((division) => ListTile(
                            enabled: unavailable == null,
                            leading: Icon(division.icon),
                            title: Text(division.name),
                            subtitle: Text(division.description),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: unavailable == null ? () => _invokeAgency(division) : null,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubagentDefinition {
  final String name;
  final String description;
  final IconData icon;

  const _SubagentDefinition({
    required this.name,
    required this.description,
    required this.icon,
  });
}

class _AgencyDivision {
  final String name;
  final String description;
  final IconData icon;

  const _AgencyDivision(this.name, this.description, this.icon);
}
