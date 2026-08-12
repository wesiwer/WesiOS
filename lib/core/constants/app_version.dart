/// Версия приложения, показываемая в UI и используемая автообновлением.
///
/// ВАЖНО: эти значения обязаны совпадать с `version:` в pubspec.yaml.
/// Release workflow проверяет это перед сборкой и остановит релиз, если
/// значения снова разойдутся.
class AppVersion {
  static const String number = '0.19.21';

  /// Номер сборки — то, что стоит после `+` в pubspec.yaml.
  static const int build = 69;

  static const String stage = 'α';
  static const String display = 'v$number $stage';
}
