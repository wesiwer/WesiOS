import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';

/// Конформная калибровка ширины интервала.
///
/// Смысл в том, чтобы не предполагать форму распределения, а посмотреть,
/// насколько модель промахивалась на самом деле, и подтянуть границы ровно
/// на столько.
void main() {
  group('конформный множитель', () {
    test('малой выборки не хватает — калибровки нет', () {
      expect(conformalScale([1, 1, 1, 1, 1, 1, 1]), 0,
          reason: 'семь наблюдений — это не статистика');
    });

    test('границы угаданы ровно — множитель около единицы', () {
      final ratios = List<double>.filled(40, 1.0);
      expect(conformalScale(ratios), closeTo(1.0, 0.01));
    });

    test('модель промахивалась вдвое — интервал расширяется', () {
      // Восемьдесят процентов промахов укладываются в 2 полуширины.
      final ratios = <double>[
        for (var i = 0; i < 32; i++) 2.0,
        for (var i = 0; i < 8; i++) 2.6,
      ];
      expect(conformalScale(ratios), greaterThan(1.9));
    });

    test('интервал был втрое шире нужного — сужается, но не схлопывается',
        () {
      final ratios = List<double>.filled(40, 0.3);
      final scale = conformalScale(ratios);
      expect(scale, lessThan(0.7));
      expect(scale, greaterThanOrEqualTo(0.55),
          reason: 'нельзя ужимать интервал до нуля по одной удачной серии');
    });

    test('поправка на конечную выборку делает интервал шире, а не уже', () {
      // Двадцать одинаковых наблюдений: без поправки квантиль пришёлся бы
      // на 16-е, с поправкой (n+1)/n — на 17-е, то есть на бо́льшую ошибку.
      final ratios = <double>[for (var i = 1; i <= 20; i++) i * 0.1];
      final scale = conformalScale(ratios);
      expect(scale, greaterThanOrEqualTo(1.7),
          reason: 'с малой выборкой обещанные 80% требуют запаса: $scale');
    });
  });

  group('точка ретро-проверки', () {
    BacktestPoint point(double actual) => BacktestPoint(
          date: DateTime(2026, 1, 1),
          actual: actual,
          p10: 800,
          p50: 1000,
          p90: 1300,
        );

    test('промах вниз не говорит ничего о верхней границе', () {
      final p = point(900);
      expect(p.lowerRatio, closeTo(0.5, 0.001), reason: '100 из 200');
      expect(p.upperRatio, isNull);
    });

    test('промах вверх меряется своей полушириной', () {
      final p = point(1450);
      expect(p.upperRatio, closeTo(1.5, 0.001), reason: '450 из 300');
      expect(p.lowerRatio, isNull);
    });

    test('нулевая полуширина — делить не на что', () {
      final flat = BacktestPoint(
        date: DateTime(2026, 1, 1),
        actual: 900,
        p10: 1000,
        p50: 1000,
        p90: 1000,
      );
      expect(flat.lowerRatio, isNull);
      expect(flat.upperRatio, isNull);
    });
  });
}
