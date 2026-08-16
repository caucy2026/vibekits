import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/pp_ocr_v6.dart';

void main() {
  test('parses PP-OCRv6 multilingual character dictionary', () {
    final String config = File(
      'test_data${Platform.pathSeparator}models${Platform.pathSeparator}'
      'ppocrv6_tiny${Platform.pathSeparator}rec.yml',
    ).readAsStringSync();
    final List<String> dictionary = parsePaddleCharacterDictionary(config);
    expect(dictionary.length, greaterThan(1000));
    expect(dictionary, containsAll(<String>['A', '中', '日', ' ']));
  });

  test('CTC decoder removes blanks and repeated indices', () {
    final Float32List values = Float32List.fromList(<double>[
      0.9,
      0.1,
      0.0,
      0.0,
      0.9,
      0.1,
      0.0,
      0.8,
      0.2,
      0.9,
      0.1,
      0.0,
      0.0,
      0.1,
      0.9,
    ]);
    final result = decodePaddleCtc(
      values,
      const <int>[1, 5, 3],
      const <String>['A', 'B'],
    );
    expect(result.text, 'AB');
    expect(result.confidence, closeTo(0.9, 0.001));
  });

  test('PP-OCRv6 tiny performs end-to-end OCR on official image', () {
    if (!Platform.isWindows) return;
    final String separator = Platform.pathSeparator;
    final String nativeDirectory = <String>[
      Directory.current.path,
      'build',
      'windows',
      'x64',
      'runner',
      'Debug',
    ].join(separator);
    final String modelDirectory = <String>[
      Directory.current.path,
      'test_data',
      'models',
      'ppocrv6_tiny',
    ].join(separator);
    final PpOcrResult result = runPpOcrSync(
      PpOcrRequest(
        imagePath: <String>[
          Directory.current.path,
          'test_data',
          'images',
          'general_ocr_002.png',
        ].join(separator),
        detectionModelPath: '$modelDirectory${separator}det.onnx',
        recognitionModelPath: '$modelDirectory${separator}rec.onnx',
        recognitionConfigPath: '$modelDirectory${separator}rec.yml',
        nativeDirectory: nativeDirectory,
      ),
    );
    expect(result.imageWidth, greaterThan(100));
    expect(result.imageHeight, greaterThan(100));
    expect(result.lines, isNotEmpty);
    expect(result.text.trim().length, greaterThan(10));
    for (final String expected in <String>[
      'BOARDING',
      'FLIGHT',
      'ZHANGQIWEI',
    ]) {
      expect(result.text, contains(expected));
    }
    expect(
      result.lines.every(
        (OcrTextLine line) =>
            line.bounds.width > 0 &&
            line.bounds.height > 0 &&
            line.confidence.isFinite,
      ),
      isTrue,
    );
  });
}
