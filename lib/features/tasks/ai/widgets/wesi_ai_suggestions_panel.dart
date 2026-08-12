import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../organizations/services/organization_context.dart';
import '../../../team/services/team_service.dart';
import '../../../treasury/services/treasury_service.dart';
import '../../models/task_model.dart';
import '../../services/task_service.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';
import '../services/wesi_ai_task_service.dart';
import 'ai_suggestion_edit_dialog.dart';

class WesiAiSuggestionsPanel extends StatefulWidget {
  final VoidCallback? onTaskCreated;

  const WesiAiSuggestionsPanel({super.key, this.onTaskCreated});

  @override
  State<WesiAiSuggestionsPanel> createState() => _WesiAiSuggestionsPanelState();
}

class _WesiAiSuggestionsPanelState extends State<WesiAiSuggestionsPanel> {
  AiTaskAnalysisResult? _result;
  bool _loading = true;
  bool _expanded = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
    TaskService.revision.addListener(_scheduleReload);
    TeamService.revision.addListener(_scheduleReload);
    OrganizationContext.revision.addListener(_scheduleReload);
    TreasuryService.revision.addListener(_scheduleReload);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    TaskService.revision.removeListener(_scheduleReload);
    TeamService.revision.removeListener(_scheduleReload);
    OrganizationContext.revision.removeListener(_scheduleReload);
    TreasuryService.revision.removeListener(_scheduleReload);
    super.dispose();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reload);
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await WesiAiTaskService.analyze();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _accept(AiTaskSuggestion suggestion) async {
    try {
      final task = await WesiAiTaskService.accept(suggestion);
      widget.onTaskCreated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Создана задача «${task.title}»')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать задачу: $error')),
      );
    }
  }

  Future<void> _edit(AiTaskSuggestion suggestion) async {
    final edited = await AiSuggestionEditDialog.show(context, suggestion);
    if (edited == null || !mounted) return;
    final current = _result;
    if (current == null) return;
    setState(() {
      _result = AiTaskAnalysisResult(
        suggestions: current.suggestions
            .map((item) => item.id == edited.id ? edited : item)
            .toList(),
        businessSignal: current.businessSignal,
        analyzedAt: current.analyzedAt,
      );
    });
  }

  Future<void> _snooze(AiTaskSuggestion suggestion) async {
    await WesiAiTaskService.snooze(suggestion);
    if (!mounted) return;
    _removeCard(suggestion.id);
  }

  Future<void> _reject(AiTaskSuggestion suggestion) async {
    await WesiAiTaskService.reject(suggestion);
    if (!mounted) return;
    _removeCard(suggestion.id);
  }

  void _removeCard(String id) {
    final current = _result;
    if (current == null) return;
    setState(() {
      _result = AiTaskAnalysisResult(
        suggestions:
            current.suggestions.where((item) => item.id != id).toList(),
        businessSignal: current.businessSignal,
        analyzedAt: current.analyzedAt,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _result?.suggestions ?? const <AiTaskSuggestion>[];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withOpacity(.26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 17, color: AppTheme.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Wesi AI · Предложения',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            if (!_loading && suggestions.isNotEmpty) ...[
                              const SizedBox(width: 7),
                              _countBadge(suggestions.length),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _headerHint(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Обновить анализ',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: AppTheme.glassBorder),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: AppTheme.accentRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Анализ временно недоступен. Обычные задачи продолжают работать.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ),
                    TextButton(
                        onPressed: _reload, child: const Text('Повторить')),
                  ],
                ),
              )
            else if (!_loading && suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 18, color: AppTheme.accentGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Сейчас нет достаточно обоснованных предложений. Wesi AI не создаёт задачи ради активности.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              )
            else if (suggestions.isNotEmpty)
              SizedBox(
                height: 236,
                child: ListView.separated(
                  padding: const EdgeInsets.all(10),
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 9),
                  itemBuilder: (context, index) =>
                      _suggestionCard(suggestions[index]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _headerHint() {
    if (_loading)
      return 'Анализирую задачи, загрузку команды и бизнес-сигналы…';
    final signal = _result?.businessSignal;
    if (signal?.salesPressure == true) {
      return 'Есть финансовый сигнал: приоритет получают действия, способные приблизить доход.';
    }
    if (signal?.financeAvailable == true) {
      return 'Учитываю историю работы, роли, загрузку, отдых и Wesi Horizon.';
    }
    return 'Учитываю историю работы, роли, загрузку и отдых. Финансы недоступны этому профилю.';
  }

  Widget _suggestionCard(AiTaskSuggestion suggestion) {
    final person = suggestion.assigneeId == null
        ? null
        : TeamService.byId(suggestion.assigneeId!);
    return Container(
      width: 350,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tag(suggestion.category.ru),
              const SizedBox(width: 6),
              _tag(_priorityLabel(suggestion.priority),
                  accent: suggestion.priority.index >= TaskPriority.high.index),
              const Spacer(),
              Tooltip(
                message: 'Отклонить на 14 дней',
                child: InkWell(
                  onTap: () => _reject(suggestion),
                  child: Icon(Icons.close_rounded,
                      size: 17, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            suggestion.whyNow,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(Icons.person_outline_rounded,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  person == null
                      ? 'Исполнитель не выбран'
                      : '${person.displayName} · ${person.position}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.trending_up_rounded,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                'Влияние на прогноз: ${suggestion.forecastImpact.ru.toLowerCase()}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
              ),
              const Spacer(),
              Text(
                'Нужно: ${(suggestion.needScore * 100).round()}%',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
          if (suggestion.evidence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '• ${suggestion.evidence.first}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 9.8),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: () => _snooze(suggestion),
                child: const Text('Не сейчас'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _edit(suggestion),
                child: const Text('Изменить'),
              ),
              const SizedBox(width: 7),
              FilledButton(
                onPressed: () => _accept(suggestion),
                child: const Text('Создать'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, {bool accent = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: (accent ? AppTheme.accent : AppTheme.surface).withOpacity(.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                accent ? AppTheme.accent.withOpacity(.4) : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: accent ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _countBadge(int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: AppTheme.accent,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  static String _priorityLabel(TaskPriority priority) => switch (priority) {
        TaskPriority.low => 'Низкая',
        TaskPriority.normal => 'Обычная',
        TaskPriority.high => 'Высокая',
        TaskPriority.urgent => 'Срочная',
      };
}
