import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Wesi AI — ассистент поверх собственных данных компании.
///
/// Ключевая мысль: ассистент отвечает не «вообще», а по данным Treasury,
/// задач, CRM и базы знаний — иначе он не отличается от любого чата в
/// браузере. Поэтому модуль осмысленно делать после того, как эти данные
/// реально появятся.
class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: 'Wesi AI',
      subtitle: ru
          ? 'Ассистент, который отвечает по вашим данным, а не вообще'
          : 'An assistant that answers from your data, not in general',
      icon: Icons.auto_awesome,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Вопросы на естественном языке: «сколько я потратил на рекламу в июне?»'
            : 'Plain-language questions: "how much did I spend on ads in June?"',
        ru
            ? 'Разбор финансов: объяснить всплеск расходов, найти аномалию'
            : 'Finance analysis: explain a spending spike, surface an anomaly',
        ru
            ? 'Поиск и краткие выжимки по базе знаний'
            : 'Search and summarise across the knowledge base',
        ru
            ? 'Черновики писем и коммерческих предложений по данным CRM'
            : 'Draft emails and proposals from CRM data',
        ru
            ? 'Голосовой ввод (Wesi Voice) как способ задать вопрос'
            : 'Voice input (Wesi Voice) as a way to ask',
        ru
            ? 'Выбор провайдера и ключа — как у Firebase, ключ хранится локально'
            : 'Pick a provider and key — stored locally, same as Firebase config',
      ],
      child: Column(
        children: [
          StubBlock(
            icon: Icons.forum,
            height: 180,
            label: ru
                ? 'Диалог с ассистентом'
                : 'Conversation with the assistant',
          ),
          const SizedBox(height: 12),
          StubBlock(
            icon: Icons.tips_and_updates,
            height: 90,
            label: ru
                ? 'Подсказки: что можно спросить по вашим данным'
                : 'Prompts: what you can ask about your own data',
          ),
        ],
      ),
    );
  }
}
