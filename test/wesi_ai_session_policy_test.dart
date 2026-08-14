import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_session_policy.dart';

void main() {
  setUp(WesiAiSessionPolicy.resetForTest);

  test('first module opening in a process starts fresh', () {
    expect(
      WesiAiSessionPolicy.shouldStartFresh(DateTime(2026, 8, 14, 10)),
      isTrue,
    );
  });

  test('return from another module resumes recent conversation', () {
    final opened = DateTime(2026, 8, 14, 10);
    final left = opened.add(const Duration(hours: 2));
    WesiAiSessionPolicy.markModuleOpened(opened);
    WesiAiSessionPolicy.markModuleClosed(left);

    expect(
      WesiAiSessionPolicy.shouldStartFresh(
        left.add(const Duration(minutes: 12)),
      ),
      isFalse,
    );
  });

  test('thirty minutes away starts a fresh conversation', () {
    final opened = DateTime(2026, 8, 14, 10);
    final left = opened.add(const Duration(minutes: 5));
    WesiAiSessionPolicy.markModuleOpened(opened);
    WesiAiSessionPolicy.markModuleClosed(left);

    expect(
      WesiAiSessionPolicy.shouldStartFresh(
        left.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });

  test('backgrounding app forces a fresh conversation on next opening', () {
    final opened = DateTime(2026, 8, 14, 10);
    WesiAiSessionPolicy.markModuleOpened(opened);
    WesiAiSessionPolicy.markAppBackgrounded();

    expect(
      WesiAiSessionPolicy.shouldStartFresh(
        opened.add(const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });
}
