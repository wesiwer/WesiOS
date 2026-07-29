import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// CRM — клиенты, сделки и история отношений с ними.
class CrmScreen extends StatelessWidget {
  const CrmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: 'CRM',
      subtitle: ru
          ? 'Клиенты, сделки и вся история общения с ними'
          : 'Clients, deals, and the full history of every relationship',
      icon: Icons.people_alt,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Карточка клиента: контакты, реквизиты, заметки'
            : 'Client card: contacts, billing details, notes',
        ru
            ? 'Воронка сделок по стадиям с суммами'
            : 'Deal pipeline by stage, with amounts',
        ru
            ? 'История касаний: звонки, письма, встречи'
            : 'Interaction history: calls, emails, meetings',
        ru
            ? 'Связь сделки с транзакцией в Treasury'
            : 'Link a closed deal to its Treasury transaction',
        ru
            ? 'Напоминания «связаться повторно»'
            : 'Follow-up reminders',
      ],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StubBlock(
                  icon: Icons.person_search,
                  height: 150,
                  label: ru ? 'Список клиентов' : 'Client list',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: StubBlock(
                  icon: Icons.filter_alt_outlined,
                  height: 150,
                  label: ru ? 'Воронка сделок' : 'Deal pipeline',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StubBlock(
            icon: Icons.history,
            height: 90,
            label: ru ? 'История касаний' : 'Interaction timeline',
          ),
        ],
      ),
    );
  }
}
