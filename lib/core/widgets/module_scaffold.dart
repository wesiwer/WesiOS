import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';
import 'wesi_wordmark.dart';
import 'window_controls.dart';

/// Стадия готовности модуля. Показывается плашкой в шапке экрана, чтобы
/// при возврате к проекту сразу было видно, где настоящая функциональность,
/// а где ещё макет — без этого через месяц невозможно вспомнить, что из
/// увиденного работает, а что нарисовано.
enum ModuleStage {
  /// Экран-макет: разметка есть, данных и логики нет.
  planned,

  /// Часть работает, часть — заглушки.
  partial,

  /// Полноценный модуль.
  ready,
}

extension ModuleStageX on ModuleStage {
  String get labelRu => switch (this) {
        ModuleStage.planned => 'В разработке',
        ModuleStage.partial => 'Частично готов',
        ModuleStage.ready => 'Работает',
      };

  String get labelEn => switch (this) {
        ModuleStage.planned => 'In development',
        ModuleStage.partial => 'Partially ready',
        ModuleStage.ready => 'Live',
      };

  Color get color => switch (this) {
        ModuleStage.planned => AppTheme.textMuted,
        ModuleStage.partial => AppTheme.accentOrange,
        ModuleStage.ready => AppTheme.accentGreen,
      };

  IconData get icon => switch (this) {
        ModuleStage.planned => Icons.construction,
        ModuleStage.partial => Icons.pending_actions,
        ModuleStage.ready => Icons.check_circle,
      };
}

/// Единая обёртка для экранов модулей: заголовок, подзаголовок, честная
/// плашка готовности и место под содержимое.
///
/// Смысл в том, чтобы все будущие разделы выглядели как один продукт и
/// чтобы статус «это ещё макет» нельзя было потерять.
class ModuleScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final ModuleStage stage;

  /// Что уже задумано в этом модуле — короткий список, который виден прямо
  /// на экране. Это и есть «чтобы можно было понимать, что будет».
  final List<String> plannedFeatures;

  /// Необязательное живое содержимое поверх макета (например, реальный
  /// календарь в модуле календаря).
  final Widget? child;

  const ModuleScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stage,
    this.plannedFeatures = const [],
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: WesiTitle(title, size: 18),
        // Резерв справа под системные кнопки окна — иначе заголовок/действия
        // уезжают под «свернуть/закрыть» кастомного title bar.
        actions: const [SizedBox(width: 140)],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, kHasCustomTitleBar ? 8 : 20, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppTheme.accentOrange.withOpacity(0.12),
                  border: Border.all(
                      color: AppTheme.accentOrange.withOpacity(0.3)),
                ),
                child: Icon(icon, color: AppTheme.accentOrange, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: WesiTitle(title, size: 20)),
                        SizedBox(width: 10),
                        _stageBadge(ru),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) ...[
            SizedBox(height: 24),
            child!,
          ],
          if (plannedFeatures.isNotEmpty) ...[
            SizedBox(height: 28),
            Text(
              ru ? 'Что здесь будет' : 'What goes here',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...plannedFeatures.map(_featureRow),
          ],
          if (stage != ModuleStage.ready) ...[
            const SizedBox(height: 28),
            _stubNotice(ru),
          ],
        ],
      ),
    );
  }

  Widget _stageBadge(bool ru) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: stage.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stage.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stage.icon, size: 12, color: stage.color),
          const SizedBox(width: 5),
          Text(
            ru ? stage.labelRu : stage.labelEn,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: stage.color),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 6),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentOrange.withOpacity(0.7),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stubNotice(bool ru) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              ru
                  ? 'Это макет будущего раздела: расположение и состав блоков '
                      'уже видны, но данные пока не подключены. Так задумано — '
                      'чтобы было понятно, каким модуль станет.'
                  : 'This is a layout preview: the structure is in place, but '
                      'no live data is wired up yet — intentionally, so the '
                      'shape of the module is visible early.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка-заглушка внутри макета — прямоугольник с подписью вместо
/// будущего графика/списка. Явно помечена, чтобы не путать с рабочим блоком.
class StubBlock extends StatelessWidget {
  final String label;
  final IconData icon;
  final double height;

  const StubBlock({
    super.key,
    required this.label,
    required this.icon,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.surface.withOpacity(0.3),
        border: Border.all(
          color: AppTheme.glassBorder,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppTheme.textMuted.withOpacity(0.6)),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textMuted.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }
}
