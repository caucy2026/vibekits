import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/vad_inference.dart';

void main() {
  test('Silero ONNX 对官方中文 WAV 完成真实离线推理', () async {
    if (!Platform.isWindows) return;
    const String modelFile = String.fromEnvironment(
      'VAD_MODEL',
      defaultValue: 'silero_vad.onnx',
    );
    final String pubCache =
        Platform.environment['PUB_CACHE'] ??
        '${Platform.environment['LOCALAPPDATA']}${Platform.pathSeparator}Pub'
            '${Platform.pathSeparator}Cache';
    final String packageRoot =
        '$pubCache${Platform.pathSeparator}hosted'
        '${Platform.pathSeparator}pub.dev${Platform.pathSeparator}'
        'sherpa_onnx_windows-1.13.5';
    final List<String> nativeCandidates = <String>[
      'build${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
          '${Platform.pathSeparator}runner${Platform.pathSeparator}Release',
      'build${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
          '${Platform.pathSeparator}runner${Platform.pathSeparator}Debug',
      '$packageRoot${Platform.pathSeparator}windows',
    ];
    final String nativeDirectory = nativeCandidates.firstWhere(
      (String directory) =>
          File('$directory${Platform.pathSeparator}onnxruntime.dll')
              .existsSync(),
      orElse: () => nativeCandidates.last,
    );
    final VadInferenceResult result = runVadInference(
      modelPath:
          'test_data${Platform.pathSeparator}models'
          '${Platform.pathSeparator}$modelFile',
      wavPath:
          'test_data${Platform.pathSeparator}audio'
          '${Platform.pathSeparator}lei-jun-test.wav',
      nativeLibraryDirectory: nativeDirectory,
    );

    expect(result.runtimeVersion, isNotEmpty);
    expect(result.audioDurationSeconds, greaterThan(1));
    expect(result.segments, isNotEmpty);
    expect(result.speechDurationSeconds, greaterThan(1));
    expect(
      result.segments.every(
        (VoiceSegment segment) =>
            segment.startSeconds >= 0 &&
            segment.endSeconds > segment.startSeconds &&
            segment.endSeconds <= result.audioDurationSeconds + 0.1,
      ),
      isTrue,
    );
  });
}
