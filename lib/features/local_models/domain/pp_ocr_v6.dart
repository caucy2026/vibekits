import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'onnx_bridge.dart';

class OcrRect {
  const OcrRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.confidence,
    required this.bounds,
  });

  final String text;
  final double confidence;
  final OcrRect bounds;
}

class PpOcrResult {
  const PpOcrResult({
    required this.lines,
    required this.imageWidth,
    required this.imageHeight,
    required this.elapsed,
    required this.runtime,
  });

  final List<OcrTextLine> lines;
  final int imageWidth;
  final int imageHeight;
  final Duration elapsed;
  final String runtime;

  String get text => lines.map((OcrTextLine line) => line.text).join('\n');
}

class PpOcrRequest {
  const PpOcrRequest({
    required this.imagePath,
    required this.detectionModelPath,
    required this.recognitionModelPath,
    required this.recognitionConfigPath,
    this.nativeDirectory,
    this.threadCount = 1,
    this.maxImagePixels = 40 * 1000 * 1000,
    this.maxDetectionSide = 1920,
  });

  final String imagePath;
  final String detectionModelPath;
  final String recognitionModelPath;
  final String recognitionConfigPath;
  final String? nativeDirectory;
  final int threadCount;
  final int maxImagePixels;
  final int maxDetectionSide;
}

Future<PpOcrResult> runPpOcr(PpOcrRequest request) {
  return Isolate.run(() => runPpOcrSync(request));
}

PpOcrResult runPpOcrSync(PpOcrRequest request) {
  final Stopwatch stopwatch = Stopwatch()..start();
  final Uint8List bytes = File(request.imagePath).readAsBytesSync();
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('图片损坏或当前解码器不支持该格式');
  if (decoded.width < 1 || decoded.height < 1) {
    throw const FormatException('图片尺寸无效');
  }
  if (decoded.width * decoded.height > request.maxImagePixels) {
    throw StateError(
      '图片像素 ${decoded.width}×${decoded.height} 超过安全上限 '
      '${request.maxImagePixels}，请先缩小图片或调整限制。',
    );
  }
  final img.Image source = img.bakeOrientation(decoded);
  final List<String> dictionary = parsePaddleCharacterDictionary(
    File(request.recognitionConfigPath).readAsStringSync(),
  );
  final OnnxBridge bridge = OnnxBridge.load(
    nativeDirectory: request.nativeDirectory,
  );
  final OnnxSession detection = bridge.openSession(
    request.detectionModelPath,
    threadCount: request.threadCount,
  );
  final OnnxSession recognition = bridge.openSession(
    request.recognitionModelPath,
    threadCount: request.threadCount,
  );

  try {
    final _DetectionInput detectionInput = _prepareDetection(
      source,
      maxSide: request.maxDetectionSide,
    );
    final OnnxTensorResult detectionOutput = detection.run(
      detectionInput.values,
      <int>[1, 3, detectionInput.height, detectionInput.width],
    );
    final List<OcrRect> boxes = _decodeDetection(
      detectionOutput,
      originalWidth: source.width,
      originalHeight: source.height,
    );

    final List<OcrTextLine> lines = <OcrTextLine>[];
    for (final OcrRect box in boxes) {
      final img.Image crop = img.copyCrop(
        source,
        x: box.left,
        y: box.top,
        width: box.width,
        height: box.height,
      );
      final _RecognitionInput recInput = _prepareRecognition(crop);
      final OnnxTensorResult recOutput = recognition.run(recInput.values, <int>[
        1,
        3,
        48,
        recInput.width,
      ]);
      final ({String text, double confidence}) decodedLine = decodePaddleCtc(
        recOutput.values,
        recOutput.shape,
        dictionary,
      );
      if (decodedLine.text.isNotEmpty) {
        lines.add(
          OcrTextLine(
            text: decodedLine.text,
            confidence: decodedLine.confidence,
            bounds: box,
          ),
        );
      }
    }
    stopwatch.stop();
    return PpOcrResult(
      lines: lines,
      imageWidth: source.width,
      imageHeight: source.height,
      elapsed: stopwatch.elapsed,
      runtime: 'PP-OCRv6_tiny / ONNX Runtime 1.27.1 CPU',
    );
  } finally {
    recognition.close();
    detection.close();
  }
}

List<String> parsePaddleCharacterDictionary(String yaml) {
  final List<String> lines = yaml.replaceAll('\r\n', '\n').split('\n');
  final int start = lines.indexWhere(
    (String line) => line.trim() == 'character_dict:',
  );
  if (start < 0) throw const FormatException('识别模型配置缺少 character_dict');
  final int baseIndent = _leadingSpaces(lines[start]);
  final List<String> characters = <String>[];
  for (int index = start + 1; index < lines.length; index++) {
    final String line = lines[index];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final int indent = _leadingSpaces(line);
    final String content = line.substring(indent);
    if (indent < baseIndent ||
        (indent == baseIndent && !content.startsWith('-'))) {
      break;
    }
    if (!content.startsWith('-')) continue;
    characters.add(_parseYamlScalar(content.substring(1).trimLeft()));
  }
  if (characters.isEmpty) {
    throw const FormatException('识别模型字符表为空');
  }
  if (characters.last != ' ') characters.add(' ');
  return List<String>.unmodifiable(characters);
}

({String text, double confidence}) decodePaddleCtc(
  Float32List output,
  List<int> shape,
  List<String> dictionary,
) {
  if (shape.length != 3 || shape[0] != 1) {
    throw FormatException('识别输出形状应为 [1,T,C]，实际为 $shape');
  }
  final int timeSteps = shape[1];
  final int classes = shape[2];
  if (output.length != timeSteps * classes) {
    throw FormatException('识别输出长度与形状不一致：${output.length} / $shape');
  }
  final StringBuffer text = StringBuffer();
  final List<double> probabilities = <double>[];
  int previous = -1;
  for (int step = 0; step < timeSteps; step++) {
    final int offset = step * classes;
    int bestIndex = 0;
    double bestValue = output[offset];
    for (int index = 1; index < classes; index++) {
      final double value = output[offset + index];
      if (value > bestValue) {
        bestValue = value;
        bestIndex = index;
      }
    }
    if (bestIndex > 0 && bestIndex != previous) {
      final int characterIndex = bestIndex - 1;
      if (characterIndex >= 0 && characterIndex < dictionary.length) {
        text.write(dictionary[characterIndex]);
        probabilities.add(bestValue);
      }
    }
    previous = bestIndex;
  }
  final double confidence = probabilities.isEmpty
      ? 0
      : probabilities.reduce((double a, double b) => a + b) /
            probabilities.length;
  return (text: text.toString(), confidence: confidence);
}

class _DetectionInput {
  const _DetectionInput({
    required this.values,
    required this.width,
    required this.height,
  });

  final Float32List values;
  final int width;
  final int height;
}

_DetectionInput _prepareDetection(img.Image source, {required int maxSide}) {
  final int safeMaxSide = maxSide.clamp(256, 4000);
  double scale = 1;
  final int minimumSide = math.min(source.width, source.height);
  if (minimumSide < 64) scale = 64 / minimumSide;
  int width = math.max(32, ((source.width * scale) / 32).round() * 32);
  int height = math.max(32, ((source.height * scale) / 32).round() * 32);
  if (math.max(width, height) > safeMaxSide) {
    final double limitScale = safeMaxSide / math.max(width, height);
    width = math.max(32, ((width * limitScale) / 32).floor() * 32);
    height = math.max(32, ((height * limitScale) / 32).floor() * 32);
  }
  final img.Image resized = img.copyResize(
    source,
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );
  final int plane = width * height;
  final Float32List values = Float32List(3 * plane);
  const List<double> mean = <double>[0.485, 0.456, 0.406];
  const List<double> std = <double>[0.229, 0.224, 0.225];
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final img.Pixel pixel = resized.getPixel(x, y);
      final int offset = y * width + x;
      values[offset] = (pixel.b / 255 - mean[0]) / std[0];
      values[offset + plane] = (pixel.g / 255 - mean[1]) / std[1];
      values[offset + 2 * plane] = (pixel.r / 255 - mean[2]) / std[2];
    }
  }
  return _DetectionInput(values: values, width: width, height: height);
}

class _RecognitionInput {
  const _RecognitionInput({required this.values, required this.width});

  final Float32List values;
  final int width;
}

_RecognitionInput _prepareRecognition(img.Image source) {
  const int targetHeight = 48;
  const int baseWidth = 320;
  const int maxWidth = 3200;
  final double ratio = source.width / math.max(1, source.height);
  final double maxWhRatio = math.max(baseWidth / targetHeight, ratio);
  final int width = (targetHeight * maxWhRatio).truncate().clamp(1, maxWidth);
  final int resizedWidth = math.min(width, (targetHeight * ratio).ceil());
  final img.Image resized = img.copyResize(
    source,
    width: resizedWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );
  final int plane = targetHeight * width;
  final Float32List values = Float32List(3 * plane);
  for (int y = 0; y < targetHeight; y++) {
    for (int x = 0; x < resizedWidth; x++) {
      final img.Pixel pixel = resized.getPixel(x, y);
      final int offset = y * width + x;
      values[offset] = pixel.b / 127.5 - 1;
      values[offset + plane] = pixel.g / 127.5 - 1;
      values[offset + 2 * plane] = pixel.r / 127.5 - 1;
    }
  }
  return _RecognitionInput(values: values, width: width);
}

List<OcrRect> _decodeDetection(
  OnnxTensorResult output, {
  required int originalWidth,
  required int originalHeight,
}) {
  if (output.shape.length != 4 || output.shape[0] != 1) {
    throw FormatException('检测输出形状应为 [1,1,H,W]，实际为 ${output.shape}');
  }
  final int height = output.shape[2];
  final int width = output.shape[3];
  if (output.values.length != height * width) {
    throw FormatException('检测输出长度与形状不一致：${output.values.length}');
  }
  final Uint8List visited = Uint8List(width * height);
  final Int32List queue = Int32List(width * height);
  final List<_ProbabilityRect> regions = <_ProbabilityRect>[];
  const double threshold = 0.2;
  const double boxThreshold = 0.4;
  const int maxCandidates = 3000;

  for (int start = 0; start < output.values.length; start++) {
    if (visited[start] != 0 || output.values[start] <= threshold) continue;
    int head = 0;
    int tail = 1;
    queue[0] = start;
    visited[start] = 1;
    int left = start % width;
    int right = left;
    int top = start ~/ width;
    int bottom = top;
    int count = 0;
    double score = 0;
    while (head < tail) {
      final int current = queue[head++];
      final int x = current % width;
      final int y = current ~/ width;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      count++;
      score += output.values[current];
      for (int dy = -1; dy <= 1; dy++) {
        final int ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final int nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final int next = ny * width + nx;
          if (visited[next] == 0 && output.values[next] > threshold) {
            visited[next] = 1;
            queue[tail++] = next;
          }
        }
      }
    }
    if (count < 3 || score / count < boxThreshold) continue;
    final int boxWidth = right - left + 1;
    final int boxHeight = bottom - top + 1;
    if (math.min(boxWidth, boxHeight) < 3) continue;
    final double area = boxWidth * boxHeight.toDouble();
    final double perimeter = 2 * (boxWidth + boxHeight).toDouble();
    final int expand = math.max(1, (area * 1.4 / perimeter).round());
    regions.add(
      _ProbabilityRect(
        left: math.max(0, left - expand),
        top: math.max(0, top - expand),
        right: math.min(width - 1, right + expand),
        bottom: math.min(height - 1, bottom + expand),
      ),
    );
    if (regions.length >= maxCandidates) break;
  }

  final List<OcrRect> boxes = regions
      .map(
        (_ProbabilityRect region) => OcrRect(
          left: (region.left * originalWidth / width).round().clamp(
            0,
            originalWidth - 1,
          ),
          top: (region.top * originalHeight / height).round().clamp(
            0,
            originalHeight - 1,
          ),
          right: ((region.right + 1) * originalWidth / width).round().clamp(
            1,
            originalWidth,
          ),
          bottom: ((region.bottom + 1) * originalHeight / height).round().clamp(
            1,
            originalHeight,
          ),
        ),
      )
      .where((OcrRect box) => box.width > 3 && box.height > 3)
      .toList();
  boxes.sort((OcrRect a, OcrRect b) {
    final int y = a.top.compareTo(b.top);
    if ((a.top - b.top).abs() < 10) return a.left.compareTo(b.left);
    return y;
  });
  return boxes;
}

class _ProbabilityRect {
  const _ProbabilityRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
}

int _leadingSpaces(String value) {
  int count = 0;
  while (count < value.length && value.codeUnitAt(count) == 0x20) {
    count++;
  }
  return count;
}

String _parseYamlScalar(String value) {
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1).replaceAll("''", "'");
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value
        .substring(1, value.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
  }
  return value;
}
