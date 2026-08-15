enum WesiAiTurnIntent { control, steer, deferred }

class WesiAiTurnIntentClassifier {
  static WesiAiTurnIntent classify(
    String text, {
    required bool hasActiveWork,
  }) {
    if (!hasActiveWork) return WesiAiTurnIntent.deferred;
    final value = _normalize(text);
    if (value.isEmpty) return WesiAiTurnIntent.deferred;

    if (_isExplicitControl(value)) return WesiAiTurnIntent.control;
    if (_isExplicitDeferred(value)) return WesiAiTurnIntent.deferred;
    if (_looksLikeCorrection(value)) return WesiAiTurnIntent.steer;
    return WesiAiTurnIntent.deferred;
  }

  static bool invalidatesDeferred(String text) {
    final value = _normalize(text);
    return value.contains('не делай') ||
        value.contains('не надо') ||
        value.contains('не нужно') ||
        value.contains('вообще не') ||
        value.contains('вместо этого') ||
        value.contains('только ') ||
        value.contains('не весь') ||
        value.contains('не всё') ||
        value.contains('не все') ||
        value.contains('сначала только') ||
        RegExp(r'\bнужн(?:а|о|ы)?\s+не\b').hasMatch(value);
  }

  static bool _isExplicitControl(String value) {
    const exact = <String>{
      'стой',
      'стоп',
      'остановись',
      'прекрати',
      'отмени',
      'хватит',
      'всё стоп',
      'все стоп',
    };
    if (exact.contains(value)) return true;
    return RegExp(
      r'^(стой|стоп|остановись|прекрати|отмени|хватит)(\b|[,.!?:;])',
    ).hasMatch(value) ||
        value.startsWith('не делай это') ||
        value.startsWith('дальше не продолжай') ||
        value.startsWith('ничего больше не делай');
  }

  static bool _isExplicitDeferred(String value) {
    return value.startsWith('после этого ') ||
        value.startsWith('потом ') ||
        value.startsWith('затем ') ||
        value.startsWith('когда закончишь') ||
        value.startsWith('когда закончите') ||
        value.startsWith('и после этого ') ||
        value.startsWith('а после этого ') ||
        value.startsWith('и отдельно ') ||
        value.startsWith('а ещё потом ') ||
        value.startsWith('а еще потом ') ||
        value.startsWith('не забудь потом ') ||
        value.startsWith('после завершения ');
  }

  static bool _looksLikeCorrection(String value) {
    if (RegExp(r'^(нет|неа)[,!. ]').hasMatch('$value ')) return true;
    const markers = <String>[
      'не так',
      'неправильно',
      'ты делаешь не',
      'ты сделал не',
      'ты взял не',
      'ты выбрал не',
      'не ту версию',
      'не тот файл',
      'не тот экран',
      'не то ',
      'нужно не ',
      'надо не ',
      'вместо этого',
      'исправь это',
      'исправь сейчас',
      'учти сейчас',
      'учти это',
      'поменяй текущ',
      'измени текущ',
      'оставь только ',
      'делай только ',
      'проверяй только ',
      'не весь ',
      'не всё ',
      'не все ',
    ];
    return markers.any(value.contains);
  }

  static String _normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}
