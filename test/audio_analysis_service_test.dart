import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/audio_analysis_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

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
    expect(raw.quality.dominantFrequencyHz, closeTo(440, 5));
    expect(raw.quality.thdPercent, lessThan(1));
    expect(raw.quality.score, greaterThanOrEqualTo(70));

    final String wavPath = '${temp.path}${Platform.pathSeparator}tone.wav';
    await AudioAnalysisService.pcmToWav(rawPath, wavPath, format);
    final AudioAnalysisResult wav = AudioAnalysisService.inspectSync(wavPath);
    expect(wav.container, 'WAV');
    expect(wav.format.sampleRate, 16000);
    expect(wav.format.channels, 1);
    expect(wav.durationSeconds, closeTo(1, 0.001));

    final String generated = await AudioAnalysisService.generateToneWav(
      '${temp.path}${Platform.pathSeparator}generated.wav',
      frequencyHz: 1000,
      durationSeconds: 0.25,
      format: format,
    );
    final AudioAnalysisResult generatedResult =
        AudioAnalysisService.inspectSync(generated);
    expect(generatedResult.quality.dominantFrequencyHz, closeTo(1000, 5));

    final HarnessToolCallResult harnessResult =
        await VibekitsHarnessToolBridge().invoke(
          toolId: VibekitsHarnessToolBridge.audioInspectId,
          arguments: <String, Object?>{'path': generated},
          approve: (_) async => true,
        );
    expect(harnessResult.ok, isTrue);
    final Map<String, Object?> quality =
        harnessResult.data!['quality']! as Map<String, Object?>;
    expect(quality['dominantFrequencyHz']! as double, closeTo(1000, 5));
  });

  test('Harness locates harmonic and noise hotspots on the timeline', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'vibekits_audio_timeline_',
    );
    addTearDown(() => temp.delete(recursive: true));
    const int sampleRate = 16000;
    const int seconds = 3;
    final math.Random random = math.Random(42);
    final ByteData pcm = ByteData(sampleRate * seconds * 2);
    for (int index = 0; index < sampleRate * seconds; index++) {
      final double time = index / sampleRate;
      double sample = math.sin(2 * math.pi * 440 * time) * 0.45;
      if (time >= 1 && time < 2) {
        sample += math.sin(2 * math.pi * 880 * time) * 0.22;
      }
      if (time >= 2) {
        sample += (random.nextDouble() * 2 - 1) * 0.25;
      }
      pcm.setInt16(
        index * 2,
        (sample.clamp(-0.99, 0.99) * 32767).round(),
        Endian.little,
      );
    }
    final String path = '${temp.path}${Platform.pathSeparator}timeline.wav';
    final String raw = '${temp.path}${Platform.pathSeparator}timeline.pcm';
    await File(raw).writeAsBytes(pcm.buffer.asUint8List());
    await AudioAnalysisService.pcmToWav(
      raw,
      path,
      const PcmAudioFormat(
        sampleRate: sampleRate,
        channels: 1,
        bitsPerSample: 16,
      ),
    );

    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.audioInspectId,
          arguments: <String, Object?>{'path': path},
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    final Map<String, Object?> summary =
        result.data!['timelineSummary']! as Map<String, Object?>;
    final List<Object?> harmonics =
        summary['harmonicHotspots']! as List<Object?>;
    final List<Object?> noise = summary['noiseHotspots']! as List<Object?>;
    expect(harmonics, isNotEmpty);
    expect(noise, isNotEmpty);
    final Map<String, Object?> harmonic =
        harmonics.first! as Map<String, Object?>;
    final Map<String, Object?> noisy = noise.first! as Map<String, Object?>;
    expect(harmonic['startSeconds']! as double, inInclusiveRange(1.0, 2.0));
    expect(noisy['startSeconds']! as double, greaterThanOrEqualTo(2.0));
  });
}
