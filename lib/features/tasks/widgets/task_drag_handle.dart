import 'package:flutter/material.dart';

import '../../../core/feedback/wesi_feedback.dart';
import '../models/task_model.dart';

/// Решает, когда карточка задачи начинает перетаскиваться.
///
/// Палец не умеет отличать «взять карточку» от «прокрутить доску»: и то, и
/// другое начинается одинаково — касание и движение вниз. Пока карточка
/// захватывалась сразу, побеждала всегда она: любая попытка пролистать
/// список уносила задачу в соседний этап, и прокрутить экран было почти
/// невозможно.
///
/// Удержание разводит эти намерения по времени: короткое движение — прокрутка,
/// задержка — захват. Отклик при захвате обязателен: до первого движения на
/// экране ничего не меняется, а сама карточка в этот момент под пальцем, и
/// понять, взялась она или нет, иначе неоткуда.
///
/// На мыши такой развязки не нужно — колесо прокручивает, кнопка тянет, — и
/// заставлять её ждать полсекунды значит портить то, что и так работало.
class TaskDragHandle extends StatelessWidget {
  final TaskModel task;
  final Widget child;
  final Widget feedback;

  /// Обычно вычисляется по платформе. Задаётся напрямую только в проверках:
  /// подменить платформу целиком дороже и менее наглядно.
  final bool? requireLongPress;

  const TaskDragHandle({
    super.key,
    required this.task,
    required this.child,
    required this.feedback,
    this.requireLongPress,
  });

  static bool needsLongPress(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final dimmed = Opacity(opacity: 0.35, child: child);
    final longPress =
        requireLongPress ?? needsLongPress(Theme.of(context).platform);

    if (!longPress) {
      return Draggable<TaskModel>(
        data: task,
        feedback: feedback,
        childWhenDragging: dimmed,
        child: child,
      );
    }
    return LongPressDraggable<TaskModel>(
      data: task,
      feedback: feedback,
      childWhenDragging: dimmed,
      // Через общий отклик приложения, а не напрямую: он собирает на
      // Android 12+ отчётливый рисунок вместо тупого толчка и молчит, если
      // вибрация выключена в настройках.
      onDragStarted: WesiFeedback.select,
      child: child,
    );
  }
}
