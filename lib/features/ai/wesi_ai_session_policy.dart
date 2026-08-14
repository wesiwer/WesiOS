/// Process-level policy for deciding whether Wesi AI should resume the active
/// conversation or start with a clean chat.
///
/// The state intentionally lives only in memory:
/// - switching between WesiOS modules keeps the same process session;
/// - backgrounding/closing the app marks the next AI opening as fresh;
/// - killing/restarting the process naturally resets this class;
/// - staying away from Wesi AI for 30 minutes also starts a fresh chat.
class WesiAiSessionPolicy {
  static const Duration resumeWindow = Duration(minutes: 30);

  static DateTime? _lastModuleOpenAt;
  static bool _backgrounded = false;

  const WesiAiSessionPolicy._();

  static bool shouldStartFresh([DateTime? now]) {
    final at = now ?? DateTime.now();
    final last = _lastModuleOpenAt;
    if (_backgrounded || last == null) return true;
    return at.difference(last) >= resumeWindow;
  }

  static void markModuleOpened([DateTime? now]) {
    _lastModuleOpenAt = now ?? DateTime.now();
    _backgrounded = false;
  }

  static void markAppBackgrounded() {
    _backgrounded = true;
  }

  /// Primarily useful for deterministic unit tests.
  static void resetForTest() {
    _lastModuleOpenAt = null;
    _backgrounded = false;
  }
}
