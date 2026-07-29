import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// База знаний — внутренняя вики компании: регламенты, инструкции, решения.
///
/// Пока макет. Редактор уже заложен в зависимостях (`flutter_quill`), поэтому
/// богатый текст здесь реалистичен, а не фантазия.
class KnowledgeBaseScreen extends StatelessWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: ru ? 'База знаний' : 'Knowledge Base',
      subtitle: ru
          ? 'Регламенты, инструкции и накопленный опыт компании в одном месте'
          : 'Playbooks, guides, and accumulated company know-how in one place',
      icon: Icons.menu_book,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Дерево разделов и статей с вложенностью'
            : 'Nested tree of sections and articles',
        ru
            ? 'Редактор с форматированием, списками и вставкой картинок'
            : 'Rich editor with formatting, lists, and image embeds',
        ru
            ? 'Полнотекстовый поиск по всей базе'
            : 'Full-text search across every article',
        ru
            ? 'Теги и связи между статьями («см. также»)'
            : 'Tags and cross-links between articles',
        ru
            ? 'История правок: кто и что менял'
            : 'Revision history: who changed what',
        ru
            ? 'Шаблоны документов (регламент, инструкция, разбор инцидента)'
            : 'Document templates (policy, how-to, incident post-mortem)',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StubBlock(
                  icon: Icons.account_tree,
                  height: 180,
                  label: ru ? 'Дерево разделов' : 'Section tree',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: StubBlock(
                  icon: Icons.article,
                  height: 180,
                  label: ru ? 'Текст статьи' : 'Article body',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StubBlock(
            icon: Icons.search,
            height: 70,
            label: ru ? 'Поиск по базе знаний' : 'Search across the base',
          ),
        ],
      ),
    );
  }
}
