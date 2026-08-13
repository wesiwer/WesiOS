import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../audio/services/audio_vault_service.dart';
import '../../../crm/services/crm_service.dart';
import '../../../files/services/file_share_service.dart';
import '../../../organizations/services/organization_context.dart';
import '../../../roadmap/services/roadmap_service.dart';
import '../../../team/services/team_service.dart';
import '../../../treasury/services/treasury_service.dart';
import '../../services/task_service.dart';
import '../models/ai_task_suggestion.dart';
import '../services/wesi_ai_task_service.dart';
import 'ai_suggestion_edit_dialog.dart';
import 'wesi_ai_suggestion_card.dart';

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

  /// Всё, из чего система теперь берёт поводы для предложений.
  ///
  /// Список обязан совпадать с источниками в `WesiAiTaskService`: если
  /// подключить источник, но забыть подписку, заведённый клиент или новая
  /// лицензия не появятся в панели, пока случайно не изменится что-то другое.
  List<ValueNotifier<int>> get _sources => [
        TaskService.revision,
        TeamService.revision,
        OrganizationContext.revision,
        TreasuryService.revision,
        CrmService.revision,
        RoadmapService.revision,
        AudioVaultService.revision,
        FileShareService.revision,
      ];

  @override
  void initState() {
    super.initState();
    _reload();
    for (final source in _sources) {
      source.addListener(_scheduleReload);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final source in _sources) {
      source.removeListener(_scheduleReload);
    }
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
        organizationName: current.organizationName,
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
        organizationName: current.organizationName,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _result?.suggestions ?? const <AiTaskSuggestion>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final cardWidth = compact
            ? math.max(260.0, constraints.maxWidth - 20).toDouble()
            : 350.0;
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
              _header(suggestions, compact),
              if (_expanded) ...[
                Divider(height: 1, color: AppTheme.glassBorder),
                if (_error != null)
                  _errorState(compact)
                else if (!_loading && suggestions.isEmpty)
                  _emptyState()
                else if (suggestions.isNotEmpty)
                  SizedBox(
                    // Высота полосы карточек задана числом, потому что
                    // горизонтальному списку нужна опора. Но число нельзя
                    // подбирать на глаз: стоило добавить в карточку одну
                    // строку — и кнопки «Создать», «Изменить», «Не сейчас»
                    // вылезли за границу. Наружу они не просто не видны, они
                    // ещё и не нажимаются: Flutter не ловит касания за
                    // пределами родителя. Выглядит это как «кнопки не
                    // работают», а причина в вёрстке.
                    //
                    // Поэтому высота растёт вместе с системным шрифтом: у
                    // человека с крупным текстом иначе ломалось бы то же
                    // самое, и без его снимка экрана об этом никто бы не
                    // узнал.
                    height: WesiAiSuggestionCard.stripHeight(context,
                        compact: compact),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      scrollDirection: Axis.horizontal,
                      itemCount: suggestions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        return WesiAiSuggestionCard(
                          suggestion: suggestion,
                          width: cardWidth,
                          compact: compact,
                          onAccept: () => _accept(suggestion),
                          onEdit: () => _edit(suggestion),
                          onSnooze: () => _snooze(suggestion),
                          onReject: () => _reject(suggestion),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _header(List<AiTaskSuggestion> suggestions, bool compact) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 14, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          compact
                              ? 'Wesi AI · Задачи'
                              : 'Wesi AI · Предложения',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (!_loading && suggestions.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _countBadge(suggestions.length),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _headerHint(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              )
            else if (!compact)
              IconButton(
                tooltip: 'Обновить анализ',
                visualDensity: VisualDensity.compact,
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: AppTheme.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(bool compact) {
    final text = Text(
      'Анализ временно недоступен. Обычные задачи продолжают работать.',
      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppTheme.accentRed),
                const SizedBox(width: 8),
                Expanded(child: text),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _reload, child: const Text('Повторить')),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: AppTheme.accentRed),
          const SizedBox(width: 8),
          Expanded(child: text),
          TextButton(onPressed: _reload, child: const Text('Повторить')),
        ],
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: AppTheme.accentGreen,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Сейчас нет достаточно обоснованных предложений. Wesi AI не создаёт задачи ради активности.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
              ),
            ),
          ],
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

  String _headerHint() {
    if (_loading) {
      return 'Анализирую задачи, загрузку команды и бизнес-сигналы…';
    }
    // Разбор идёт по одной организации, и это не мелочь: те же данные в
    // соседней организации дадут другой список. Пока названия не было,
    // понять, про чью работу говорит панель, было неоткуда.
    final org = _result?.organizationName.trim() ?? '';
    final prefix = org.isEmpty ? '' : '$org · ';
    final signal = _result?.businessSignal;
    if (signal?.salesPressure == true) {
      return '${prefix}есть финансовый сигнал: приоритет получают действия, способные приблизить доход.';
    }
    if (signal?.financeAvailable == true) {
      return '${prefix}учитываю бизнес-цепочку, узкие места, историю, ваши решения, загрузку и Wesi Horizon.';
    }
    return '${prefix}учитываю бизнес-цепочку, узкие места, историю, ваши решения и загрузку. Финансы недоступны этому профилю.';
  }

}
