import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/audio_analysis_service.dart';

void main() {
  test('analyzes raw PCM and generated WAV without clipping', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'vibekits_audio_',
    );
    addTearDown(() => temp.delete(recursive: true));
    const PcmAudioFormat format = PcmAudioFormat(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );
    final ByteData pcm = ByteData(16000 * 2);
    for (int index = 0; index < 16000; index++) {
      final int sample = (math.sin(2 * math.pi * 440 * index / 16000) * 16384)
          .round();
      pcm.setInt16(index * 2, sample, Endian.little);
    }
    final String rawPath = '${temp.path}${Platform.pathSeparator}tone.pcm';
    await File(rawPath).writeAsBytes(pcm.buffer.asUint8List());

    final AudioAnalysisResult raw = AudioAnalysisService.inspectSync(
      rawPath,
      rawFormat: format,
    );
    expect(raw.container, 'RAW PCM');
    expect(raw.durationSeconds, closeTo(1, 0.001));
    expect(raw.peak.single, closeTo(0.5, 0.01));
    expect(raw.rms.single, closeTo(0.3535, 0.01));
    expect(raw.clippedRatio, 0);
    expect(raw.waveformMin.single, isNotEmpty);
    expect(raw.spectrum, isNotEmpty);

    final String wavPath = '${temp.path}${Platform.pathSeparator}tone.wav';
    await AudioAnalysisService.pcmToWav(rawPath, wavPath, format);
    final AudioAnalysisResult wav = AudioAnalysisService.inspectSync(wavPath);
    expect(wav.container, 'WAV');
    expect(wav.format.sampleRate, 16000);
    expect(wav.format.channels, 1);
    expect(wav.durationSeconds, closeTo(1, 0.001));
  });
}
