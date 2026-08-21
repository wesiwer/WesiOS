/// Версия приложения, показываемая в UI и используемая автообновлением.
///
/// ВАЖНО: эти значения обязаны совпадать с `version:` в pubspec.yaml.
/// Release workflow проверяет это перед сборкой и остановит релиз, если
/// значения снова разойдутся.
class AppVersion {
  static const String number = '0.22.35';

  /// Номер сборки — то, что стоит после `+` в pubspec.yaml.
  ///
  /// Нужен автообновлению: когда версия не менялась, а сборка пересобрана,
  /// сравнивать по одному лишь `number` нечем. Обязан совпадать с pubspec.
  static const int build = 110;

  static const String stage = 'α';
  static const String display = 'v$number $stage';
}
