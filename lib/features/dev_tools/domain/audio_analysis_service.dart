import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

class PcmAudioFormat {
  const PcmAudioFormat({
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitsPerSample = 16,
    this.signed = true,
    this.littleEndian = true,
    this.floatingPoint = false,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final bool signed;
  final bool littleEndian;
  final bool floatingPoint;

  int get bytesPerSample => bitsPerSample ~/ 8;
  int get bytesPerFrame => bytesPerSample * channels;

  Map<String, Object?> toJson() => <String, Object?>{
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
    'signed': signed,
    'littleEndian': littleEndian,
    'floatingPoint': floatingPoint,
  };

  static PcmAudioFormat fromJson(Map<String, Object?> json) => PcmAudioFormat(
    sampleRate: _positiveInt(json['sampleRate'], 48000),
    channels: _positiveInt(json['channels'], 2).clamp(1, 8),
    bitsPerSample: <int>{8, 16, 24, 32}.contains(json['bitsPerSample'])
        ? json['bitsPerSample']! as int
        : 16,
    signed: json['signed'] != false,
    littleEndian: json['littleEndian'] != false,
    floatingPoint: json['floatingPoint'] == true,
  );

  static int _positiveInt(Object? value, int fallback) {
    final int parsed = value is int
        ? value
        : int.tryParse('$value') ?? fallback;
    return parsed > 0 ? parsed : fallback;
  }
}

class AudioAnalysisResult {
  const AudioAnalysisResult({
    required this.path,
    required this.container,
    required this.format,
    required this.fileBytes,
    required this.frames,
    required this.durationSeconds,
    required this.peak,
    required this.rms,
    required this.dcOffset,
    required this.clippedRatio,
    required this.silenceRatio,
    required this.waveformMin,
    required this.waveformMax,
    required this.spectrum,
    required this.quality,
    required this.findings,
  });

  final String path;
  final String container;
  final PcmAudioFormat format;
  final int fileBytes;
  final int frames;
  final double durationSeconds;
  final List<double> peak;
  final List<double> rms;
  final List<double> dcOffset;
  final double clippedRatio;
  final double silenceRatio;
  final List<List<double>> waveformMin;
  final List<List<double>> waveformMax;
  final List<double> spectrum;
  final AudioSignalQuality quality;
  final List<String> findings;

  Map<String, Object?> toJson({bool includeVisualData = false}) =>
      <String, Object?>{
        'path': path,
        'container': container,
        'format': format.toJson(),
        'fileBytes': fileBytes,
        'frames': frames,
        'durationSeconds': durationSeconds,
        'peak': peak,
        'peakDbfs': peak.map(_dbfs).toList(growable: false),
        'rms': rms,
        'rmsDbfs': rms.map(_dbfs).toList(growable: false),
        'dcOffset': dcOffset,
        'clippedRatio': clippedRatio,
        'silenceRatio': silenceRatio,
        'quality': quality.toJson(),
        'findings': findings,
        if (includeVisualData) 'waveformMin': waveformMin,
        if (includeVisualData) 'waveformMax': waveformMax,
        if (includeVisualData) 'spectrum': spectrum,
      };

  static double _dbfs(double value) =>
      value <= 0 ? -120 : 20 * math.log(value) / math.ln10;
}

class AudioSignalQuality {
  const AudioSignalQuality({
    required this.dominantFrequencyHz,
    required this.fundamentalDbfs,
    required this.harmonicsDb,
    required this.thdPercent,
    required this.thdnPercent,
    required this.estimatedSnrDb,
    required this.noiseFloorDbfs,
    required this.crestFactorDb,
    required this.channelCorrelation,
    required this.tonalConfidence,
    required this.estimatedEffectiveBits,
    required this.score,
  });

  final double dominantFrequencyHz;
  final double fundamentalDbfs;
  final List<double> harmonicsDb;
  final double thdPercent;
  final double thdnPercent;
  final double estimatedSnrDb;
  final double noiseFloorDbfs;
  final List<double> crestFactorDb;
  final double? channelCorrelation;
  final double tonalConfidence;
  final double estimatedEffectiveBits;
  final int score;

  Map<String, Object?> toJson() => <String, Object?>{
    'dominantFrequencyHz': dominantFrequencyHz,
    'fundamentalDbfs': fundamentalDbfs,
    'harmonicsDbRelativeToFundamental': harmonicsDb,
    'thdPercent': thdPercent,
    'thdnPercent': thdnPercent,
    'estimatedSnrDb': estimatedSnrDb,
    'noiseFloorDbfs': noiseFloorDbfs,
    'crestFactorDb': crestFactorDb,
    'channelCorrelation': channelCorrelation,
    'tonalConfidence': tonalConfidence,
    'estimatedEffectiveBits': estimatedEffectiveBits,
    'qualityScore': score,
    'measurementNote': 'THD/THD+N/SNR 为稳态单音估算；复杂语音或音乐只作诊断参考。',
  };
}

abstract final class AudioAnalysisService {
  static const int waveformBins = 1200;
  static const int fftSize = 4096;

  static Future<AudioAnalysisResult> inspect(
    String path, {
    PcmAudioFormat rawFormat = const PcmAudioFormat(),
  }) => Isolate.run(() => inspectSync(path, rawFormat: rawFormat));

  static AudioAnalysisResult inspectSync(
    String path, {
    PcmAudioFormat rawFormat = const PcmAudioFormat(),
  }) {
    final File file = File(path);
    if (!file.existsSync()) throw ArgumentError('音频文件不存在：$path');
    final Uint8List bytes = file.readAsBytesSync();
    if (bytes.isEmpty) throw const FormatException('音频文件为空');
    final _DecodedAudio decoded = _decode(bytes, rawFormat);
    final PcmAudioFormat format = decoded.format;
    if (format.sampleRate < 1000 || format.sampleRate > 768000) {
      throw FormatException('采样率超出合理范围：${format.sampleRate} Hz');
    }
    if (format.bytesPerFrame <= 0 ||
        decoded.audioBytes.length < format.bytesPerFrame) {
      throw const FormatException('没有完整 PCM 帧');
    }
    final int frames = decoded.audioBytes.length ~/ format.bytesPerFrame;
    final ByteData audioData = ByteData.sublistView(decoded.audioBytes);
    final int bins = math.min(waveformBins, frames);
    final List<List<double>> minimum = List<List<double>>.generate(
      format.channels,
      (_) => List<double>.filled(bins, 1),
    );
    final List<List<double>> maximum = List<List<double>>.generate(
      format.channels,
      (_) => List<double>.filled(bins, -1),
    );
    final List<double> peak = List<double>.filled(format.channels, 0);
    final List<double> squareSum = List<double>.filled(format.channels, 0);
    final List<double> sum = List<double>.filled(format.channels, 0);
    int clipped = 0;
    int silent = 0;
    final Float64List fftInput = Float64List(math.min(fftSize, frames));
    double channelCrossSum = 0;

    for (int frame = 0; frame < frames; frame++) {
      double mixed = 0;
      for (int channel = 0; channel < format.channels; channel++) {
        final int offset =
            frame * format.bytesPerFrame + channel * format.bytesPerSample;
        final double sample = _sample(
          decoded.audioBytes,
          audioData,
          offset,
          format,
        ).clamp(-1.0, 1.0);
        final double absolute = sample.abs();
        peak[channel] = math.max(peak[channel], absolute);
        squareSum[channel] += sample * sample;
        sum[channel] += sample;
        if (absolute >= 0.999) clipped++;
        if (absolute <= 0.001) silent++;
        final int bin = frame * bins ~/ frames;
        minimum[channel][bin] = math.min(minimum[channel][bin], sample);
        maximum[channel][bin] = math.max(maximum[channel][bin], sample);
        mixed += sample;
      }
      if (format.channels >= 2) {
        final int base = frame * format.bytesPerFrame;
        channelCrossSum +=
            _sample(decoded.audioBytes, audioData, base, format) *
            _sample(
              decoded.audioBytes,
              audioData,
              base + format.bytesPerSample,
              format,
            );
      }
      if (frame < fftInput.length) fftInput[frame] = mixed / format.channels;
    }
    final int samples = frames * format.channels;
    final List<double> rms = squareSum
        .map((double value) => math.sqrt(value / frames))
        .toList(growable: false);
    final List<double> dc = sum
        .map((double value) => value / frames)
        .toList(growable: false);
    final double clippedRatio = clipped / samples;
    final double silenceRatio = silent / samples;
    final double? correlation = format.channels < 2
        ? null
        : _correlation(
            frames,
            channelCrossSum,
            sum[0],
            sum[1],
            squareSum[0],
            squareSum[1],
          );
    final AudioSignalQuality quality = _signalQuality(
      fftInput,
      format.sampleRate,
      peak,
      rms,
      correlation,
      clippedRatio,
    );
    final List<String> findings = <String>[];
    if (clippedRatio > 0.0001) {
      findings.add('检测到削波 ${(clippedRatio * 100).toStringAsFixed(3)}%');
    }
    if (silenceRatio > 0.95) findings.add('超过 95% 采样接近静音');
    if (dc.any((double value) => value.abs() > 0.01)) findings.add('存在明显直流偏置');
    if (peak.every((double value) => value < 0.01)) {
      findings.add('整体电平很低，可能是静音或格式参数错误');
    }
    if (decoded.trailingBytes > 0) {
      findings.add('末尾有 ${decoded.trailingBytes} 字节不完整 PCM 帧');
    }
    if (quality.tonalConfidence >= 0.1) {
      if (quality.thdPercent > 5) {
        findings.add('谐波失真偏高：THD ${quality.thdPercent.toStringAsFixed(2)}%');
      }
      if (quality.estimatedSnrDb < 40) {
        findings.add('估算信噪比较低：${quality.estimatedSnrDb.toStringAsFixed(1)} dB');
      }
    } else {
      findings.add('输入不是明显稳态单音，THD/SNR 仅作参考；语音和音乐应结合频谱与电平判断');
    }
    if (correlation != null && correlation < -0.8) {
      findings.add('左右声道高度反相，单声道合并时可能抵消');
    }
    if (findings.isEmpty) findings.add('未发现明显削波、静音或直流偏置异常');

    return AudioAnalysisResult(
      path: file.absolute.path,
      container: decoded.container,
      format: format,
      fileBytes: bytes.length,
      frames: frames,
      durationSeconds: frames / format.sampleRate,
      peak: peak,
      rms: rms,
      dcOffset: dc,
      clippedRatio: clippedRatio,
      silenceRatio: silenceRatio,
      waveformMin: minimum,
      waveformMax: maximum,
      spectrum: _spectrum(fftInput),
      quality: quality,
      findings: findings,
    );
  }

  static Future<String> pcmToWav(
    String inputPath,
    String outputPath,
    PcmAudioFormat format,
  ) => Isolate.run(() {
    final Uint8List pcm = File(inputPath).readAsBytesSync();
    final Uint8List wav = _wavBytes(pcm, format);
    File(outputPath).parent.createSync(recursive: true);
    File(outputPath).writeAsBytesSync(wav, flush: true);
    return File(outputPath).absolute.path;
  });

  static Future<String> generateToneWav(
    String outputPath, {
    double frequencyHz = 1000,
    double durationSeconds = 1,
    double amplitude = 0.5,
    PcmAudioFormat format = const PcmAudioFormat(
      sampleRate: 48000,
      channels: 2,
      bitsPerSample: 16,
    ),
  }) => Isolate.run(() {
    if (frequencyHz <= 0 || frequencyHz >= format.sampleRate / 2) {
      throw ArgumentError('测试音频率必须大于 0 且低于奈奎斯特频率');
    }
    if (durationSeconds <= 0 || durationSeconds > 60) {
      throw ArgumentError('测试音时长必须在 0～60 秒之间');
    }
    if (amplitude <= 0 || amplitude > 1) {
      throw ArgumentError('测试音幅度必须在 0～1 之间');
    }
    if (format.bitsPerSample != 16 || !format.signed) {
      throw ArgumentError('测试音生成当前支持 16-bit 有符号 PCM');
    }
    final int frames = (format.sampleRate * durationSeconds).round();
    final ByteData pcm = ByteData(frames * format.bytesPerFrame);
    for (int frame = 0; frame < frames; frame++) {
      final int sample =
          (math.sin(2 * math.pi * frequencyHz * frame / format.sampleRate) *
                  amplitude *
                  32767)
              .round();
      for (int channel = 0; channel < format.channels; channel++) {
        pcm.setInt16(
          (frame * format.channels + channel) * 2,
          sample,
          format.littleEndian ? Endian.little : Endian.big,
        );
      }
    }
    final File output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(_wavBytes(pcm.buffer.asUint8List(), format));
    return output.absolute.path;
  });

  static _DecodedAudio _decode(Uint8List bytes, PcmAudioFormat rawFormat) {
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE') {
      final ByteData data = ByteData.sublistView(bytes);
      int cursor = 12;
      PcmAudioFormat? format;
      Uint8List? audio;
      while (cursor + 8 <= bytes.length) {
        final String id = ascii.decode(
          bytes.sublist(cursor, cursor + 4),
          allowInvalid: true,
        );
        final int length = data.getUint32(cursor + 4, Endian.little);
        final int start = cursor + 8;
        if (start + length > bytes.length) break;
        if (id == 'fmt ' && length >= 16) {
          final int encoding = data.getUint16(start, Endian.little);
          format = PcmAudioFormat(
            sampleRate: data.getUint32(start + 4, Endian.little),
            channels: data.getUint16(start + 2, Endian.little),
            bitsPerSample: data.getUint16(start + 14, Endian.little),
            signed: data.getUint16(start + 14, Endian.little) != 8,
            littleEndian: true,
            floatingPoint: encoding == 3,
          );
          if (encoding != 1 && encoding != 3) {
            throw FormatException('当前仅分析 PCM/IEEE Float WAV，编码为 $encoding');
          }
        } else if (id == 'data') {
          audio = Uint8List.sublistView(bytes, start, start + length);
        }
        cursor = start + length + (length.isOdd ? 1 : 0);
      }
      if (format == null || audio == null) {
        throw const FormatException('WAV 缺少 fmt 或 data 块');
      }
      return _DecodedAudio(
        'WAV',
        format,
        audio,
        audio.length % format.bytesPerFrame,
      );
    }
    return _DecodedAudio(
      'RAW PCM',
      rawFormat,
      bytes,
      bytes.length % rawFormat.bytesPerFrame,
    );
  }

  static double _sample(
    Uint8List bytes,
    ByteData data,
    int offset,
    PcmAudioFormat format,
  ) {
    final Endian endian = format.littleEndian ? Endian.little : Endian.big;
    if (format.floatingPoint && format.bitsPerSample == 32) {
      return data.getFloat32(offset, endian);
    }
    return switch (format.bitsPerSample) {
      8 =>
        format.signed
            ? data.getInt8(offset) / 128
            : (data.getUint8(offset) - 128) / 128,
      16 => data.getInt16(offset, endian) / 32768,
      24 => _int24(bytes, offset, format.littleEndian) / 8388608,
      32 => data.getInt32(offset, endian) / 2147483648,
      _ => throw FormatException('不支持 ${format.bitsPerSample} bit PCM'),
    };
  }

  static int _int24(Uint8List bytes, int offset, bool littleEndian) {
    int value = littleEndian
        ? bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16)
        : bytes[offset + 2] | (bytes[offset + 1] << 8) | (bytes[offset] << 16);
    if ((value & 0x800000) != 0) value -= 0x1000000;
    return value;
  }

  static List<double> _spectrum(Float64List input) {
    if (input.isEmpty) return const <double>[];
    final _FftSnapshot fft = _fft(input);
    final int bins = math.min(128, fft.power.length);
    return List<double>.generate(
      bins,
      (int bin) => math.sqrt(fft.power[bin]),
      growable: false,
    );
  }

  static AudioSignalQuality _signalQuality(
    Float64List input,
    int sampleRate,
    List<double> peak,
    List<double> rms,
    double? correlation,
    double clippedRatio,
  ) {
    if (input.length < 32) {
      return AudioSignalQuality(
        dominantFrequencyHz: 0,
        fundamentalDbfs: -120,
        harmonicsDb: const <double>[],
        thdPercent: 0,
        thdnPercent: 0,
        estimatedSnrDb: 0,
        noiseFloorDbfs: -120,
        crestFactorDb: List<double>.filled(peak.length, 0),
        channelCorrelation: correlation,
        tonalConfidence: 0,
        estimatedEffectiveBits: 0,
        score: 0,
      );
    }
    final _FftSnapshot fft = _fft(input);
    final List<double> power = fft.power;
    final int bins = power.length;
    final int startBin = math.max(1, (20 * fft.size / sampleRate).ceil());
    int fundamentalBin = startBin;
    for (int bin = startBin + 1; bin < bins; bin++) {
      if (power[bin] > power[fundamentalBin]) fundamentalBin = bin;
    }
    double bandPower(int center) {
      double value = 0;
      for (
        int bin = math.max(1, center - 1);
        bin <= math.min(bins - 1, center + 1);
        bin++
      ) {
        value += power[bin];
      }
      return value;
    }

    final double fundamentalPower = bandPower(fundamentalBin)
        .clamp(1e-20, double.infinity);
    double harmonicPower = 0;
    final List<double> harmonicDb = <double>[];
    final Set<int> excluded = <int>{0};
    for (int bin = fundamentalBin - 1; bin <= fundamentalBin + 1; bin++) {
      if (bin >= 0 && bin < bins) excluded.add(bin);
    }
    for (int order = 2; order <= 5; order++) {
      final int center = fundamentalBin * order;
      if (center >= bins) break;
      final double value = bandPower(center);
      harmonicPower += value;
      harmonicDb.add(
        10 *
            math.log(value.clamp(1e-20, double.infinity) / fundamentalPower) /
            math.ln10,
      );
      for (int bin = center - 1; bin <= center + 1; bin++) {
        if (bin >= 0 && bin < bins) excluded.add(bin);
      }
    }
    double totalPower = 0;
    double noisePower = 0;
    final List<double> noiseAmplitudes = <double>[];
    for (int bin = 1; bin < bins; bin++) {
      totalPower += power[bin];
      if (!excluded.contains(bin)) {
        noisePower += power[bin];
        noiseAmplitudes.add(math.sqrt(power[bin]));
      }
    }
    noiseAmplitudes.sort();
    final double medianNoise = noiseAmplitudes.isEmpty
        ? 0
        : noiseAmplitudes[noiseAmplitudes.length ~/ 2];
    final double thd = math.sqrt(harmonicPower / fundamentalPower) * 100;
    final double thdn =
        math.sqrt((harmonicPower + noisePower) / fundamentalPower) * 100;
    final double snr =
        10 *
        math.log(fundamentalPower / noisePower.clamp(1e-20, double.infinity)) /
        math.ln10;
    final double confidence =
        fundamentalPower / totalPower.clamp(1e-20, double.infinity);
    final double fundamentalAmplitude = math.sqrt(fundamentalPower);
    final List<double> crest = List<double>.generate(
      peak.length,
      (int index) =>
          20 *
          math.log(
            peak[index].clamp(1e-20, double.infinity) /
                rms[index].clamp(1e-20, double.infinity),
          ) /
          math.ln10,
      growable: false,
    );
    final double effectiveBits = ((snr - 1.76) / 6.02).clamp(0, 32);
    int score = 100;
    score -= (clippedRatio * 10000).round().clamp(0, 40);
    if (confidence >= 0.1) {
      score -= (thd * 2).round().clamp(0, 30);
      if (snr < 60) score -= ((60 - snr) / 2).round().clamp(0, 30);
    }
    return AudioSignalQuality(
      dominantFrequencyHz: fundamentalBin * sampleRate / fft.size,
      fundamentalDbfs:
          20 *
          math.log(fundamentalAmplitude.clamp(1e-20, double.infinity)) /
          math.ln10,
      harmonicsDb: harmonicDb,
      thdPercent: thd,
      thdnPercent: thdn,
      estimatedSnrDb: snr,
      noiseFloorDbfs:
          20 * math.log(medianNoise.clamp(1e-20, double.infinity)) / math.ln10,
      crestFactorDb: crest,
      channelCorrelation: correlation,
      tonalConfidence: confidence,
      estimatedEffectiveBits: effectiveBits,
      score: score.clamp(0, 100),
    );
  }

  /// Radix-2 FFT keeps interactive analysis bounded. The former direct DFT
  /// repeated trigonometric work for every bin and could take over a minute.
  static _FftSnapshot _fft(Float64List input) {
    int size = 1;
    while (size * 2 <= input.length) {
      size *= 2;
    }
    final Float64List real = Float64List(size);
    final Float64List imaginary = Float64List(size);
    double windowSum = 0;
    for (int index = 0; index < size; index++) {
      final double window = size <= 1
          ? 1
          : 0.5 - 0.5 * math.cos(2 * math.pi * index / (size - 1));
      real[index] = input[index] * window;
      windowSum += window;
    }
    for (int index = 1, reversed = 0; index < size; index++) {
      int bit = size >> 1;
      while ((reversed & bit) != 0) {
        reversed ^= bit;
        bit >>= 1;
      }
      reversed ^= bit;
      if (index < reversed) {
        final double temporary = real[index];
        real[index] = real[reversed];
        real[reversed] = temporary;
      }
    }
    for (int length = 2; length <= size; length <<= 1) {
      final double angle = -2 * math.pi / length;
      final double stepReal = math.cos(angle);
      final double stepImaginary = math.sin(angle);
      for (int start = 0; start < size; start += length) {
        double twiddleReal = 1;
        double twiddleImaginary = 0;
        for (int offset = 0; offset < length ~/ 2; offset++) {
          final int even = start + offset;
          final int odd = even + length ~/ 2;
          final double oddReal =
              real[odd] * twiddleReal - imaginary[odd] * twiddleImaginary;
          final double oddImaginary =
              real[odd] * twiddleImaginary + imaginary[odd] * twiddleReal;
          final double evenReal = real[even];
          final double evenImaginary = imaginary[even];
          real[even] = evenReal + oddReal;
          imaginary[even] = evenImaginary + oddImaginary;
          real[odd] = evenReal - oddReal;
          imaginary[odd] = evenImaginary - oddImaginary;
          final double nextReal =
              twiddleReal * stepReal - twiddleImaginary * stepImaginary;
          twiddleImaginary =
              twiddleReal * stepImaginary + twiddleImaginary * stepReal;
          twiddleReal = nextReal;
        }
      }
    }
    final double scale = windowSum <= 0 ? 1 : 2 / windowSum;
    final List<double> power = List<double>.generate(size ~/ 2, (int bin) {
      final double amplitude =
          math.sqrt(real[bin] * real[bin] + imaginary[bin] * imaginary[bin]) *
          scale;
      return amplitude * amplitude;
    }, growable: false);
    return _FftSnapshot(size, power);
  }

  static double _correlation(
    int frames,
    double crossSum,
    double sumA,
    double sumB,
    double squareA,
    double squareB,
  ) {
    final double meanA = sumA / frames;
    final double meanB = sumB / frames;
    final double covariance = crossSum / frames - meanA * meanB;
    final double varianceA = squareA / frames - meanA * meanA;
    final double varianceB = squareB / frames - meanB * meanB;
    final double denominator = math.sqrt(math.max(0, varianceA * varianceB));
    return denominator <= 1e-20 ? 0 : (covariance / denominator).clamp(-1, 1);
  }

  static Uint8List _wavBytes(Uint8List pcm, PcmAudioFormat format) {
    if (format.floatingPoint || !format.littleEndian) {
      throw const FormatException('播放转换当前要求小端整数 PCM');
    }
    final Uint8List output = Uint8List(44 + pcm.length);
    final ByteData data = ByteData.sublistView(output);
    void text(int offset, String value) =>
        output.setRange(offset, offset + value.length, ascii.encode(value));
    text(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, format.channels, Endian.little);
    data.setUint32(24, format.sampleRate, Endian.little);
    data.setUint32(28, format.sampleRate * format.bytesPerFrame, Endian.little);
    data.setUint16(32, format.bytesPerFrame, Endian.little);
    data.setUint16(34, format.bitsPerSample, Endian.little);
    text(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    output.setRange(44, output.length, pcm);
    return output;
  }
}

class _DecodedAudio {
  const _DecodedAudio(
    this.container,
    this.format,
    this.audioBytes,
    this.trailingBytes,
  );

  final String container;
  final PcmAudioFormat format;
  final Uint8List audioBytes;
  final int trailingBytes;
}

class _FftSnapshot {
  const _FftSnapshot(this.size, this.power);

  final int size;
  final List<double> power;
}
