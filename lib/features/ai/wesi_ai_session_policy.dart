/// Process-level policy for deciding whether Wesi AI should resume the active
/// conversation or start with a clean chat.
///
/// The state intentionally lives only in memory:
/// - switching between WesiOS modules can resume the same process session;
/// - backgrounding/closing the app marks the next AI opening as fresh;
/// - killing/restarting the process naturally resets this class;
/// - staying away from Wesi AI for 30 minutes also starts a fresh chat.
class WesiAiSessionPolicy {
  static const Duration resumeWindow = Duration(minutes: 30);

  static bool _openedInThisProcess = false;
  static DateTime? _lastModuleLeaveAt;
  static bool _backgrounded = false;

  const WesiAiSessionPolicy._();

  static bool shouldStartFresh([DateTime? now]) {
    final at = now ?? DateTime.now();
    if (_backgrounded || !_openedInThisProcess) return true;
    final leftAt = _lastModuleLeaveAt;
    if (leftAt == null) return false;
    return at.difference(leftAt) >= resumeWindow;
  }

  static void markModuleOpened([DateTime? now]) {
    _openedInThisProcess = true;
    _lastModuleLeaveAt = null;
    _backgrounded = false;
  }

  static void markModuleClosed([DateTime? now]) {
    if (!_openedInThisProcess || _backgrounded) return;
    _lastModuleLeaveAt = now ?? DateTime.now();
  }

  static void markAppBackgrounded() {
    _backgrounded = true;
  }

  /// Primarily useful for deterministic unit tests.
  static void resetForTest() {
    _openedInThisProcess = false;
    _lastModuleLeaveAt = null;
    _backgrounded = false;
  }
}
