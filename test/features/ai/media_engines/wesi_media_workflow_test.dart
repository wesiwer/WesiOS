import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_workflow.dart';

void main() {
  test('media workflows never execute on control plane', () async {
    final result = await WesiMediaWorkflow.run(
      const WesiMediaWorkflowRequest(
        kind: WesiMediaWorkflowKind.imageGenerate,
        prompt: 'test image',
      ),
      isWorker: false,
    );
    expect(result.ok, isFalse);
    expect(result.code, 'WAI_MEDIA_REQUIRES_WORKER');
  });

  test('edit workflow requires a real input artifact', () async {
    final result = await WesiMediaWorkflow.run(
      const WesiMediaWorkflowRequest(
        kind: WesiMediaWorkflowKind.imageEdit,
        prompt: 'edit this image',
      ),
      isWorker: true,
    );
    expect(result.ok, isFalse);
    expect(result.code, 'WAI_MEDIA_INPUT_INVALID');
  });

  test('prompt is bounded before any engine call', () async {
    final result = await WesiMediaWorkflow.run(
      WesiMediaWorkflowRequest(
        kind: WesiMediaWorkflowKind.imageGenerate,
        prompt: 'x' * (WesiMediaWorkflow.maxPromptChars + 1),
      ),
      isWorker: true,
    );
    expect(result.ok, isFalse);
    expect(result.code, 'WAI_MEDIA_REQUEST_INVALID');
  });
}
