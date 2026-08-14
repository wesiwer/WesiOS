/// Process-level policy for deciding whether Wesi AI should resume the active
/// conversation or start with a clean chat.
///
/// The state intentionally lives only in memory:
/// - switching between WesiOS modules can resume the same process session;
/// - briefly backgrounding WesiOS keeps the current AI conversation;
/// - killing/fully closing and restarting the process naturally starts fresh;
/// - staying away from the Wesi AI module for 30 minutes also starts fresh.
class WesiAiSessionPolicy {
  static const Duration resumeWindow = Duration(minutes: 30);

  static bool _openedInThisProcess = false;
  static DateTime? _lastModuleLeaveAt;

  const WesiAiSessionPolicy._();

  static bool shouldStartFresh([DateTime? now]) {
    final at = now ?? DateTime.now();
    if (!_openedInThisProcess) return true;
    final leftAt = _lastModuleLeaveAt;
    if (leftAt == null) return false;
    return at.difference(leftAt) >= resumeWindow;
  }

  static void markModuleOpened([DateTime? now]) {
    _openedInThisProcess = true;
    _lastModuleLeaveAt = null;
  }

  static void markModuleClosed([DateTime? now]) {
    if (!_openedInThisProcess) return;
    _lastModuleLeaveAt = now ?? DateTime.now();
  }

  /// Backgrounding is intentionally not treated as closing Wesi AI.
  /// Users often need to switch to another app briefly while working with AI.
  /// A full app/process restart naturally resets this in-memory policy instead.
  static void markAppBackgrounded() {}

  /// Primarily useful for deterministic unit tests.
  static void resetForTest() {
    _openedInThisProcess = false;
    _lastModuleLeaveAt = null;
  }
}
