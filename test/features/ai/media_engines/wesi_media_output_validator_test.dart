import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_output_validator.dart';

void main() {
  test('image validation requires bounded dimensions and matching format', () {
    final ok = WesiMediaOutputValidator.validate(
      mediaType: 'image',
      workflow: 'imageGenerate',
      mimeType: 'image/png',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'image': <String, dynamic>{'width': 1024, 'height': 1024, 'format': 'png'},
      },
    );
    expect(ok.ok, isTrue);

    final bad = WesiMediaOutputValidator.validate(
      mediaType: 'image',
      workflow: 'imageGenerate',
      mimeType: 'image/png',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'image': <String, dynamic>{'width': 1024, 'height': 1024, 'format': 'jpeg'},
      },
    );
    expect(bad.ok, isFalse);
    expect(bad.code, 'WAI_MEDIA_VALIDATION_MIME_MISMATCH');
  });

  test('video requires ffprobe duration container and a video stream', () {
    final ok = WesiMediaOutputValidator.validate(
      mediaType: 'video',
      workflow: 'videoCompose',
      mimeType: 'video/mp4',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'probe': <String, dynamic>{
          'engine': 'ffprobe',
          'container': 'mp4',
          'durationMs': 8000,
          'streams': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'video', 'codec': 'h264'},
            <String, dynamic>{'type': 'audio', 'codec': 'aac'},
          ],
        },
      },
    );
    expect(ok.ok, isTrue);

    final noVideo = WesiMediaOutputValidator.validate(
      mediaType: 'video',
      workflow: 'videoCompose',
      mimeType: 'video/mp4',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'probe': <String, dynamic>{
          'engine': 'ffprobe',
          'container': 'mp4',
          'durationMs': 8000,
          'streams': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'audio', 'codec': 'aac'},
          ],
        },
      },
    );
    expect(noVideo.ok, isFalse);
    expect(noVideo.code, 'WAI_MEDIA_VALIDATION_VIDEO_STREAM_MISSING');
  });

  test('music master requires a valid audio probe', () {
    final result = WesiMediaOutputValidator.validate(
      mediaType: 'music',
      workflow: 'musicMix',
      mimeType: 'audio/wav',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'probe': <String, dynamic>{
          'engine': 'ffprobe',
          'container': 'wav',
          'durationMs': 181000,
          'streams': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'audio', 'codec': 'pcm_s24le'},
          ],
        },
      },
    );
    expect(result.ok, isTrue);
  });

  test('stems archive requires hashed path-free stem evidence', () {
    final hash = List<String>.filled(64, 'a').join();
    Map<String, dynamic> stem(String name) => <String, dynamic>{
          'name': name,
          'mimeType': 'audio/wav',
          'byteSize': 4096,
          'durationMs': 120000,
          'sha256': hash,
        };

    final ok = WesiMediaOutputValidator.validate(
      mediaType: 'music',
      workflow: 'musicStems',
      mimeType: 'application/zip',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'stems': <Map<String, dynamic>>[stem('vocals'), stem('drums')],
      },
    );
    expect(ok.ok, isTrue);

    final unsafe = stem('vocals')..['path'] = '/tmp/vocals.wav';
    final rejected = WesiMediaOutputValidator.validate(
      mediaType: 'music',
      workflow: 'musicStems',
      mimeType: 'application/zip',
      evidence: <String, dynamic>{
        'validator': 'wesi-media-v1',
        'stems': <Map<String, dynamic>>[unsafe, stem('drums')],
      },
    );
    expect(rejected.ok, isFalse);
    expect(rejected.code, 'WAI_MEDIA_VALIDATION_STEMS_INVALID');
  });

  test('missing or untrusted validation evidence fails closed', () {
    final missing = WesiMediaOutputValidator.validate(
      mediaType: 'video',
      workflow: 'videoGenerate',
      mimeType: 'video/mp4',
      evidence: null,
    );
    expect(missing.code, 'WAI_MEDIA_VALIDATION_MISSING');

    final untrusted = WesiMediaOutputValidator.validate(
      mediaType: 'video',
      workflow: 'videoGenerate',
      mimeType: 'video/mp4',
      evidence: <String, dynamic>{'validator': 'model-said-ok'},
    );
    expect(untrusted.code, 'WAI_MEDIA_VALIDATION_UNTRUSTED');
  });
}
