import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vibekits/features/local_models/domain/image_preview.dart';

void main() {
  test('TGA 等非系统原生图片可转为 PNG 预览', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_image_preview',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final img.Image source = img.Image(width: 24, height: 12)
      ..clear(img.ColorRgb8(12, 100, 220));
    final File tga = File(
      '${sandbox.path}${Platform.pathSeparator}developer-texture.tga',
    )..writeAsBytesSync(img.encodeTga(source));

    final preview = buildPortableImagePreviewSync(tga.path);
    expect(preview.take(4), <int>[0x89, 0x50, 0x4e, 0x47]);
    final img.Image? decoded = img.decodePng(preview);
    expect(decoded?.width, 24);
    expect(decoded?.height, 12);
  });

  test('预览前检查像素预算而不是解码后才拒绝', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_image_budget',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final img.Image source = img.Image(width: 64, height: 64)
      ..clear(img.ColorRgba8(12, 100, 220, 128));
    final File png = File(
      '${sandbox.path}${Platform.pathSeparator}oversized.png',
    )..writeAsBytesSync(img.encodePng(source));

    expect(
      () => buildPortableImagePreviewSync(png.path, maxPixels: 1000),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('64×64'),
        ),
      ),
    );
  });

  test('P0 静态图片编码均可转换为统一 PNG 预览', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_image_formats',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final img.Image source = img.Image(width: 20, height: 10)
      ..clear(img.ColorRgba8(30, 90, 180, 220));
    final Map<String, List<int>> formats = <String, List<int>>{
      'png': img.encodePng(source),
      'jpg': img.encodeJpg(source),
      'gif': img.encodeGif(source),
      'bmp': img.encodeBmp(source),
      'tiff': img.encodeTiff(source),
      'tga': img.encodeTga(source),
      'ico': img.encodeIco(source),
      'webp': img.encodeWebP(source),
    };

    for (final MapEntry<String, List<int>> format in formats.entries) {
      final File file = File(
        '${sandbox.path}${Platform.pathSeparator}sample.${format.key}',
      )..writeAsBytesSync(format.value);
      final Uint8List preview = buildPortableImagePreviewSync(file.path);
      expect(preview.take(4), <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
      ], reason: format.key);
    }
  });
}
