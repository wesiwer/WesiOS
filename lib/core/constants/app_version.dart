/// Единственный источник версии приложения для UI (Splash, Settings).
///
/// Раньше строка версии была захардкожена по отдельности в двух экранах и в
/// README.md — легко забыть обновить одно из мест. Теперь Dart-код меняется
/// только здесь; pubspec.yaml (`version:`) и README.md обновляются вручную
/// вместе с этим файлом при бампе версии.
class AppVersion {
  static const String number = '0.19.12';

  /// Номер сборки — то, что стоит после `+` в pubspec.yaml.
  ///
  /// Нужен автообновлению: когда версия не менялась, а сборка пересобрана,
  /// сравнивать по одному лишь `number` нечем. Обязан совпадать с pubspec.
  static const int build = 60;

  static const String stage = 'α';
  static const String display = 'v$number $stage';
}