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

  test('normalizes server image edit request', () {
    final request = WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
      'mediaType': 'image',
      'prompt': 'remove background',
      'options': <String, dynamic>{
        'operation': 'edit',
        'inputs': <String>['/tmp/input.png'],
      },
    });
    expect(request, isNotNull);
    expect(request!.kind, WesiMediaWorkflowKind.imageEdit);
    expect(request.inputPaths, <String>['/tmp/input.png']);
  });

  test('normalizes stems and subtitle workflows', () {
    final stems = WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
      'mediaType': 'music',
      'prompt': 'split this track',
      'operation': 'stems',
    });
    final subtitles = WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
      'mediaType': 'video',
      'prompt': 'add subtitles',
      'options': <String, dynamic>{'operation': 'subtitles'},
    });
    expect(stems?.kind, WesiMediaWorkflowKind.musicStems);
    expect(subtitles?.kind, WesiMediaWorkflowKind.videoSubtitles);
  });

  test('rejects unsupported server media type', () {
    expect(
      WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
        'mediaType': 'binary',
        'prompt': 'do something',
      }),
      isNull,
    );
  });
}
