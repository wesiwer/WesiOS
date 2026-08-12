import 'package:flutter/foundation.dart';

import '../models/transaction_model.dart';
import 'forecast_engine.dart';

/// Всё, что нужно движку для одного расчёта.
///
/// Отдельный класс нужен потому, что в изолят уходит ровно один аргумент.
@immutable
class ForecastRequest {
  final List<TransactionModel> transactions;
  final double currentBalance;
  final int days;
  final WhatIfScenario whatIf;
  final double annualDiscountRate;
  final DateTime? asOf;

  const ForecastRequest({
    required this.transactions,
    required this.currentBalance,
    required this.days,
    this.whatIf = WhatIfScenario.none,
    this.annualDiscountRate = 0.0,
    this.asOf,
  });
}

ForecastResult _run(ForecastRequest r) => ForecastEngine.generate(
      transactions: r.transactions,
      currentBalance: r.currentBalance,
      days: r.days,
      whatIf: r.whatIf,
      annualDiscountRate: r.annualDiscountRate,
      asOf: r.asOf,
    );

/// Прогноз считается вне потока интерфейса.
///
/// Monte-Carlo — это `пути × дни` шагов плюс сортировка на каждый день.
/// Замеры на десктопе: 0,34 с на месяц, 0,74 с на три, 1,7 с на пять лет;
/// на телефоне заметно больше. Раньше всё это выполнялось прямо в потоке
/// интерфейса: метод был `async`, но сам расчёт синхронный, и `await` перед
/// синхронной работой ничего никуда не переносит. Экран замирал при каждом
/// открытии прогноза и на каждой смене периода, сценария или ставки.
///
/// Порог не случайный: короткий расчёт дешевле выполнить на месте, чем
/// заплатить за создание изолята и копирование списка операций туда и
/// обратно.
///
/// В тестах изолят не поднимаем: `compute` требует живого биндинга, а сам
/// движок детерминирован и проверяется напрямую.
Future<ForecastResult> runForecastOffThread(ForecastRequest request) async {
  final heavy = request.days * request.transactions.length > 2000;
  if (!heavy || kIsWeb) return _run(request);
  try {
    return await compute(_run, request);
  } catch (_) {
    // Изолят может не подняться (тесты, ограниченные окружения) — считаем
    // на месте: медленнее, но результат тот же.
    return _run(request);
  }
}
