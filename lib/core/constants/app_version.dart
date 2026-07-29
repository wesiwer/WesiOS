/// Единственный источник версии приложения для UI (Splash, Settings).
///
/// Раньше строка версии была захардкожена по отдельности в двух экранах и в
/// README.md — легко забыть обновить одно из мест. Теперь Dart-код меняется
/// только здесь; pubspec.yaml (`version:`) и README.md обновляются вручную
/// вместе с этим файлом при бампе версии.
class AppVersion {
  static const String number = '0.8.0';
  static const String stage = 'α';
  static const String display = 'v$number $stage';
}
