import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'audio_analysis_service.dart';

/// Audio operations shared by Harness and the visual audio workspace.
class AudioHarnessService {
  AudioPlayer? _player;
  String? _temporaryPreviewPath;

  Future<Map<String, Object?>> inspect(Map<String, Object?> arguments) async {
    final String path = _requiredPath(arguments, 'path');
    final AudioAnalysisResult result = await AudioAnalysisService.inspect(
      path,
      rawFormat: PcmAudioFormat.fromJson(arguments),
    );
    return result.toJson(
      includeVisualData: arguments['includeVisualData'] == true,
    );
  }

  Future<Map<String, Object?>> pcmToWav(Map<String, Object?> arguments) async {
    final String inputPath = _requiredPath(arguments, 'inputPath');
    final String outputPath = _requiredPath(arguments, 'outputPath');
    final String written = await AudioAnalysisService.pcmToWav(
      inputPath,
      outputPath,
      PcmAudioFormat.fromJson(arguments),
    );
    return <String, Object?>{
      'inputPath': File(inputPath).absolute.path,
      'outputPath': written,
      'bytes': await File(written).length(),
    };
  }

  Future<Map<String, Object?>> play(Map<String, Object?> arguments) async {
    final String path = _requiredPath(arguments, 'path');
    final String lowerPath = path.toLowerCase();
    String playable = path;
    if (lowerPath.endsWith('.pcm') || lowerPath.endsWith('.raw')) {
      final Directory directory = Directory(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}tmp${Platform.pathSeparator}audio',
      );
      playable =
          '${directory.path}${Platform.pathSeparator}'
          'harness_${DateTime.now().microsecondsSinceEpoch}.wav';
      playable = await AudioAnalysisService.pcmToWav(
        path,
        playable,
        PcmAudioFormat.fromJson(arguments),
      );
      final String? previous = _temporaryPreviewPath;
      _temporaryPreviewPath = playable;
      if (previous != null && previous != playable) {
        try {
          await File(previous).delete();
        } on Object {
          // The decoder may still be releasing the previous file.
        }
      }
    }
    final AudioPlayer player = _player ??= AudioPlayer();
    await player.play(DeviceFileSource(playable));
    return <String, Object?>{'state': 'playing', 'path': playable};
  }

  Future<Map<String, Object?>> pause(Map<String, Object?> arguments) async {
    final AudioPlayer? player = _player;
    if (player == null) return <String, Object?>{'state': 'idle'};
    await player.pause();
    return <String, Object?>{'state': 'paused'};
  }

  Future<Map<String, Object?>> stop(Map<String, Object?> arguments) async {
    final AudioPlayer? player = _player;
    if (player == null) return <String, Object?>{'state': 'idle'};
    await player.stop();
    return <String, Object?>{'state': 'stopped'};
  }

  Future<Map<String, Object?>> generateTone(
    Map<String, Object?> arguments,
  ) async {
    final String outputPath = _requiredPath(arguments, 'outputPath');
    final String written = await AudioAnalysisService.generateToneWav(
      outputPath,
      frequencyHz: _double(arguments['frequencyHz'], 1000),
      durationSeconds: _double(arguments['durationSeconds'], 1),
      amplitude: _double(arguments['amplitude'], 0.5),
      format: PcmAudioFormat.fromJson(arguments),
    );
    return <String, Object?>{
      'outputPath': written,
      'bytes': await File(written).length(),
      'analysis': (await AudioAnalysisService.inspect(written)).toJson(),
    };
  }

  static String _requiredPath(Map<String, Object?> arguments, String key) {
    final String value = (arguments[key] ?? '').toString().trim();
    if (value.isEmpty) throw ArgumentError('缺少 $key');
    return value;
  }

  static double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
}
