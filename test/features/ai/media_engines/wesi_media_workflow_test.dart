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

  test('server filesystem paths are ignored unless locally trusted', () {
    final request = WesiMediaWorkflow.fromLocalRequest(
      <String, dynamic>{
        'mediaType': 'image',
        'prompt': 'remove background',
        'options': <String, dynamic>{
          'operation': 'edit',
          'inputs': <String>['/untrusted/model/path.png'],
        },
      },
      trustedInputPaths: const <String>['/trusted/staged/input.png'],
    );
    expect(request, isNotNull);
    expect(request!.kind, WesiMediaWorkflowKind.imageEdit);
    expect(request.inputPaths, const <String>['/trusted/staged/input.png']);
    expect(request.options.containsKey('inputs'), isFalse);
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

  test('video generation is distinct from video composition', () {
    final generated = WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
      'mediaType': 'video',
      'prompt': 'a cinematic launch scene',
      'options': <String, dynamic>{'workflow': 'videoGenerate'},
    });
    final composed = WesiMediaWorkflow.fromLocalRequest(<String, dynamic>{
      'mediaType': 'video',
      'prompt': 'compose these clips',
      'options': <String, dynamic>{'workflow': 'videoCompose'},
    });
    expect(generated?.kind, WesiMediaWorkflowKind.videoGenerate);
    expect(generated?.requiresInput, isFalse);
    expect(composed?.kind, WesiMediaWorkflowKind.videoCompose);
    expect(composed?.requiresInput, isTrue);
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
