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
        'findings': findings,
        if (includeVisualData) 'waveformMin': waveformMin,
        if (includeVisualData) 'waveformMax': waveformMax,
        if (includeVisualData) 'spectrum': spectrum,
      };

  static double _dbfs(double value) =>
      value <= 0 ? -120 : 20 * math.log(value) / math.ln10;
}

abstract final class AudioAnalysisService {
  static const int waveformBins = 1200;
  static const int fftSize = 1024;

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
    final int bins = math.min(128, input.length ~/ 2);
    return List<double>.generate(bins, (int bin) {
      double real = 0;
      double imaginary = 0;
      for (int index = 0; index < input.length; index++) {
        final double window =
            0.5 -
            0.5 * math.cos(2 * math.pi * index / math.max(1, input.length - 1));
        final double angle = 2 * math.pi * bin * index / input.length;
        real += input[index] * window * math.cos(angle);
        imaginary -= input[index] * window * math.sin(angle);
      }
      return math.sqrt(real * real + imaginary * imaginary) / input.length;
    }, growable: false);
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
