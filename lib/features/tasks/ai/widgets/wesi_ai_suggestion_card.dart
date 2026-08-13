import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../team/services/team_service.dart';
import '../../models/task_model.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';

/// Одно предложение Wesi AI со всеми его кнопками.
///
/// Вынесено из панели не ради порядка в файлах. Карточка живёт в полосе
/// фиксированной высоты, и однажды это уже стоило работоспособности: к ней
/// добавили строку со сроком, содержимое переросло отведённую высоту и
/// вытолкнуло кнопки за пределы родителя. Снаружи они выглядели ровно так
/// же — и не нажимались, потому что Flutter не ищет попадания за границами
/// родителя. Пока карточка была замкнута внутри панели, проверить её
/// раскладку было нечем.
///
/// Здесь же исправлена и причина. Раньше кнопки прижимал книзу `Spacer`:
/// он отдаёт остаток высоты, а когда остатка нет — молча отдаёт ноль, и
/// ряд кнопок уезжает наружу. Теперь высоту первым забирает ряд кнопок, а
/// содержимому достаётся остальное; переросшее содержимое обрезается на
/// своей границе и вытолкнуть ничего не может.
class WesiAiSuggestionCard extends StatelessWidget {
  final AiTaskSuggestion suggestion;
  final double width;
  final bool compact;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onSnooze;
  final VoidCallback onReject;

  const WesiAiSuggestionCard({
    super.key,
    required this.suggestion,
    required this.width,
    required this.compact,
    required this.onAccept,
    required this.onEdit,
    required this.onSnooze,
    required this.onReject,
  });

  /// Высота полосы карточек.
  ///
  /// Учитывает системный масштаб текста: при увеличенном шрифте те же
  /// строки занимают больше места, и полоса, посчитанная по обычному,
  /// оказывается тесной. Верхняя граница нужна, чтобы на предельном
  /// масштабе полоса не съела экран целиком.
  static double stripHeight(BuildContext context, {required bool compact}) =>
      (compact ? 306.0 : 294.0) *
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);

  @override
  Widget build(BuildContext context) {
    final person = suggestion.assigneeId == null
        ? null
        : TeamService.byId(suggestion.assigneeId!);

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Прокрутка отключена намеренно: полоса листается вбок, страница
            // за ней — вниз, и третий скроллер внутри карточки перехватывал
            // бы у них жесты. Здесь он нужен только как способ дать
            // содержимому свою высоту и обрезать лишнее.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _content(person),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _actions(),
        ],
      ),
    );
  }

  List<Widget> _content(dynamic person) => [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _tag(suggestion.category.ru),
                  _tag(
                    priorityLabel(suggestion.priority),
                    accent:
                        suggestion.priority.index >= TaskPriority.high.index,
                  ),
                  // Метка происхождения: карточка указывает на конкретную
                  // сделку, веху или бит, а не на тип работ вообще. Человеку
                  // важно видеть разницу — такое предложение можно пойти и
                  // перепроверить в самом приложении.
                  if (suggestion.isFact) _tag('по данным'),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Отклонить на 14 дней',
              child: InkWell(
                onTap: onReject,
                child: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: AppTheme.textMuted,
                ),
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
        if (suggestion.strategicReason.isNotEmpty) ...[
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 13, color: AppTheme.accent),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    suggestion.strategicReason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9.8,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${(suggestion.strategicScore * 100).round()}%',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        // Подпись раньше обещала влияние на денежный прогноз, которого нет:
        // это вес в сортировке предложений. Пояснение под нажатием, а не
        // строкой в карточке: строк здесь и так больше, чем помещается.
        Tooltip(
          message: 'Значимость меняет только порядок предложений в этом '
              'списке — в денежный прогноз она не идёт.\n\n'
              'Деньги в прогноз приносят сами объекты: сделка CRM с '
              'ожидаемой датой закрытия и лицензия на бит. Считаются они '
              'по организации: своя касса — своя, у родительской — своя '
              'вместе с дочерними, у соседней — ничего.',
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 12),
          child: Row(
            children: [
              Icon(Icons.trending_up_rounded,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Значимость: ${suggestion.forecastImpact.ru.toLowerCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Нужно: ${(suggestion.needScore * 100).round()}%',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        if (suggestion.dueDate != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  // У наблюдения срок не выдуман: это дата самой лицензии,
                  // вехи или платежа. Без неё карточка теряет половину
                  // смысла — «когда» здесь так же важно, как «что».
                  'Срок: ${shortDate(suggestion.dueDate!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ],
        if (suggestion.evidence.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '• ${suggestion.evidence.first}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 9.8),
          ),
        ],
      ];

  Widget _actions() {
    ButtonStyle? tight(ButtonStyle Function({
      EdgeInsetsGeometry? padding,
      Size? minimumSize,
    }) from) =>
        compact
            ? from(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                minimumSize: const Size(0, 36),
              )
            : null;

    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onSnooze,
            style: tight(TextButton.styleFrom),
            child: const Text('Не сейчас', maxLines: 1),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: OutlinedButton(
            onPressed: onEdit,
            style: tight(OutlinedButton.styleFrom),
            child: const Text('Изменить', maxLines: 1),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: FilledButton(
            onPressed: onAccept,
            style: tight(FilledButton.styleFrom),
            child: const Text('Создать', maxLines: 1),
          ),
        ),
      ],
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
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: accent ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      );

  static String priorityLabel(TaskPriority priority) => switch (priority) {
        TaskPriority.low => 'Низкая',
        TaskPriority.normal => 'Обычная',
        TaskPriority.high => 'Высокая',
        TaskPriority.urgent => 'Срочная',
      };

  static String shortDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}';
}
