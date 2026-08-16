import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class VoiceSegment {
  const VoiceSegment({required this.startSeconds, required this.endSeconds});

  final double startSeconds;
  final double endSeconds;

  double get durationSeconds => endSeconds - startSeconds;
}

class VadInferenceResult {
  const VadInferenceResult({
    required this.segments,
    required this.audioDurationSeconds,
    required this.elapsed,
    required this.runtimeVersion,
  });

  final List<VoiceSegment> segments;
  final double audioDurationSeconds;
  final Duration elapsed;
  final String runtimeVersion;

  double get speechDurationSeconds => segments.fold<double>(
    0,
    (double total, VoiceSegment segment) => total + segment.durationSeconds,
  );
}

Future<VadInferenceResult> runVadInferenceAsync({
  required String modelPath,
  required String wavPath,
  String? nativeLibraryDirectory,
}) => Isolate.run(
  () => runVadInference(
    modelPath: modelPath,
    wavPath: wavPath,
    nativeLibraryDirectory: nativeLibraryDirectory,
  ),
);

/// 使用 sherpa-onnx + Silero VAD 在本机 CPU 分析 16kHz 单声道 WAV。
VadInferenceResult runVadInference({
  required String modelPath,
  required String wavPath,
  String? nativeLibraryDirectory,
}) {
  final Stopwatch stopwatch = Stopwatch()..start();
  if (Platform.isWindows && nativeLibraryDirectory != null) {
    // Dart FFI 用绝对路径加载主 DLL 时，Windows 不一定把同目录加入依赖搜索。
    // 先加载 ORT，避免命中 PATH 中其他架构的同名库。
    DynamicLibrary.open(
      '$nativeLibraryDirectory${Platform.pathSeparator}onnxruntime.dll',
    );
  }
  sherpa.initBindings(nativeLibraryDirectory);
  final sherpa.WaveData wave = sherpa.readWave(wavPath);
  if (wave.sampleRate != 16000) {
    throw FormatException('当前模型要求 16000 Hz WAV，输入为 ${wave.sampleRate} Hz');
  }
  if (wave.samples.isEmpty) throw const FormatException('WAV 中没有音频采样');

  final sherpa.SileroVadModelConfig silero = sherpa.SileroVadModelConfig(
    model: modelPath,
    minSilenceDuration: 0.25,
    minSpeechDuration: 0.25,
    maxSpeechDuration: 30,
  );
  final sherpa.VadModelConfig config = sherpa.VadModelConfig(
    sileroVad: silero,
    sampleRate: wave.sampleRate,
    numThreads: 1,
    debug: false,
  );
  final sherpa.VoiceActivityDetector detector = sherpa.VoiceActivityDetector(
    config: config,
    bufferSizeInSeconds: 60,
  );
  final List<VoiceSegment> segments = <VoiceSegment>[];

  void drain() {
    while (!detector.isEmpty()) {
      final sherpa.SpeechSegment segment = detector.front();
      final double start = segment.start / wave.sampleRate;
      segments.add(
        VoiceSegment(
          startSeconds: start,
          endSeconds: start + segment.samples.length / wave.sampleRate,
        ),
      );
      detector.pop();
    }
  }

  try {
    final int window = config.sileroVad.windowSize;
    final int completeWindows = wave.samples.length ~/ window;
    for (int index = 0; index < completeWindows; index++) {
      final int start = index * window;
      detector.acceptWaveform(
        Float32List.sublistView(wave.samples, start, start + window),
      );
      drain();
    }
    final int remainderStart = completeWindows * window;
    if (remainderStart < wave.samples.length) {
      final Float32List tail = Float32List(window);
      tail.setRange(
        0,
        wave.samples.length - remainderStart,
        wave.samples,
        remainderStart,
      );
      detector.acceptWaveform(tail);
    }
    detector.flush();
    drain();
  } finally {
    detector.free();
  }
  stopwatch.stop();
  return VadInferenceResult(
    segments: List<VoiceSegment>.unmodifiable(segments),
    audioDurationSeconds: wave.samples.length / wave.sampleRate,
    elapsed: stopwatch.elapsed,
    runtimeVersion: sherpa.getVersion(),
  );
}
