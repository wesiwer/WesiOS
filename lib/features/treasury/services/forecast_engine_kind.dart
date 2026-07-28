/// Один из выбираемых движков прогноза на экране Forecast.
///
/// [wesiHorizon] — родной движок ([ForecastEngine]): bootstrap Monte-Carlo,
/// разделяет доход/расход, всегда доступен (чистый Dart, без внешних
/// зависимостей). [prophet] и [sarimax] — настоящие библиотеки временных
/// рядов, вызываются через `ExternalForecastBridge` как Python-подпроцесс;
/// требуют предварительной установки через `EngineInstallService` (см. этот
/// сервис — скачивание/распаковка готового рантайма по требованию
/// пользователя). [combined] — не отдельный расчёт, а поэлементное среднее
/// по тем движкам, что реально посчитались.
///
/// Вынесено в отдельный файл, чтобы `multi_engine_forecast.dart` (сам
/// расчёт) и `engine_install_service.dart` (установка движков) могли
/// ссылаться на один и тот же тип, не создавая цикл импортов друг на друга.
enum ForecastEngineKind { wesiHorizon, prophet, sarimax, combined }

extension ForecastEngineKindX on ForecastEngineKind {
  String get nameRu => switch (this) {
        ForecastEngineKind.wesiHorizon => 'Wesi Horizon',
        ForecastEngineKind.prophet => 'Prophet',
        ForecastEngineKind.sarimax => 'SARIMAX',
        ForecastEngineKind.combined => 'Комбинированный',
      };

  String get nameEn => switch (this) {
        ForecastEngineKind.wesiHorizon => 'Wesi Horizon',
        ForecastEngineKind.prophet => 'Prophet',
        ForecastEngineKind.sarimax => 'SARIMAX',
        ForecastEngineKind.combined => 'Combined',
      };
}
