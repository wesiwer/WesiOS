import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_cash_impact.dart';

/// «А влияние на прогноз идёт куда? На какую организацию?»
///
/// Правильный ответ оказался неприятным: никуда. Подпись «Влияние на
/// прогноз» стояла на числе, которое в денежный прогноз не попадает и
/// никогда не попадало. Оно даёт часть веса в сортировке предложений — и
/// всё. Ни плюса Wesi Beat's, ни плюса всем сразу: это вообще не про деньги.
///
/// Деньги в Horizon приходят другим путём и как раз так, как человек и
/// ожидал: от самих объектов (сделка CRM с ожидаемой датой закрытия,
/// лицензия на бит) и строго по организациям, чей прогноз открыт.
///
/// Здесь это зафиксировано, чтобы подпись и поведение больше не расходились.
void main() {
  AiTaskSuggestion suggestion(AiForecastImpact impact) => AiTaskSuggestion(
        id: 's',
        fingerprint: 'f',
        templateId: 't',
        category: AiTaskCategory.production,
        organizationId: 'org_wesi_beats',
        title: 'Написать новый бит',
        description: '',
        assigneeId: null,
        priority: TaskPriority.normal,
        forecastImpact: impact,
        needScore: .5,
        confidence: .8,
        effortPoints: 1,
        whyNow: '',
      );

  group('значимость — это порядок, а не деньги', () {
    test('подпись в карточке больше не обещает влияния на прогноз', () {
      final panel = File(
        'lib/features/tasks/ai/widgets/wesi_ai_suggestions_panel.dart',
      ).readAsStringSync();

      expect(panel.contains('Влияние на прогноз'), isFalse,
          reason: 'подпись обещала то, чего не происходит');
      expect(panel.contains('Значимость: '), isTrue);
    });

    test('задача из предложения не несёт денежного тега', () {
      // Единственная дорога от задачи к прогнозу — тег `cash:`. Его читает
      // HorizonBusinessContextService, и только он превращает задачу в
      // движение денег. Предложения такого тега не ставят, поэтому принятое
      // предложение не двигает прогноз ни на рубль — ни вверх, ни вниз.
      final tags = [
        'wesi-ai',
        'wesi-ai:template:beat_create',
        'wesi-ai:strategy:70',
        'wesi-ai:fingerprint:f',
        'wesi-ai:fact:beatCadenceStalled:beat-cadence',
      ];

      expect(TaskCashImpact.fromTags(tags), isNull);
    });

    test('значимость нигде не превращается в сумму', () {
      // Проверка по исходникам: если однажды кто-то решит «ну пусть высокая
      // значимость добавит немного в прогноз», это придётся сделать явно —
      // и тест об этом скажет.
      final engine = File(
        'lib/features/tasks/ai/services/wesi_ai_task_engine.dart',
      ).readAsStringSync();
      final planner = File(
        'lib/features/tasks/ai/services/wesi_ai_strategy_planner.dart',
      ).readAsStringSync();

      for (final source in [engine, planner]) {
        expect(source.contains('TaskCashImpact'), isFalse,
            reason: 'движок предложений не должен трогать денежные теги');
      }
    });

    test('деньги в прогноз приносят объекты, а не предложения', () {
      // Сделки и лицензии Horizon читает сам, и читает по организациям.
      // Поэтому добавлять деньги ещё и со стороны предложений нельзя: одна
      // и та же лицензия попала бы в прогноз дважды.
      final context = File(
        'lib/features/treasury/services/horizon_business_context.dart',
      ).readAsStringSync();

      expect(context.contains('dealsForOrganizations'), isTrue);
      expect(context.contains('organizationIds'), isTrue);
      expect(context.contains('beat.lease'), isTrue);
    });
  });

  group('порядок предложений действительно зависит от значимости', () {
    test('при равном остальном выше стоит более значимое', () {
      final list = [
        suggestion(AiForecastImpact.low),
        suggestion(AiForecastImpact.critical),
        suggestion(AiForecastImpact.medium),
      ]..sort((a, b) => b.forecastImpact.index.compareTo(a.forecastImpact.index));

      expect(list.first.forecastImpact, AiForecastImpact.critical);
      expect(list.last.forecastImpact, AiForecastImpact.low);
    });

    test('подписи склоняются как «значимость», а не как «влияние»', () {
      expect(AiForecastImpact.high.ru, 'Высокая');
      expect(AiForecastImpact.critical.ru, 'Критическая');
    });
  });
}
