import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes developer-oriented image formats and returns a Flutter-friendly PNG.
Future<Uint8List> buildPortableImagePreview(
  String path, {
  int maxSide = 2048,
  int maxPixels = 100 * 1000 * 1000,
  int maxEncodedBytes = 256 * 1024 * 1024,
}) => Isolate.run(
  () => buildPortableImagePreviewSync(
    path,
    maxSide: maxSide,
    maxPixels: maxPixels,
    maxEncodedBytes: maxEncodedBytes,
  ),
);

Uint8List buildPortableImagePreviewSync(
  String path, {
  int maxSide = 2048,
  int maxPixels = 100 * 1000 * 1000,
  int maxEncodedBytes = 256 * 1024 * 1024,
}) {
  final File source = File(path);
  if (!source.existsSync()) throw const FileSystemException('图片不存在');
  final int encodedBytes = source.lengthSync();
  if (encodedBytes > maxEncodedBytes) {
    throw FormatException(
      '图片文件 ${(encodedBytes / 1024 / 1024).toStringAsFixed(1)} MiB 超过安全上限',
    );
  }
  final Uint8List bytes = source.readAsBytesSync();
  final img.Decoder? decoder = img.findDecoderForData(bytes);
  if (decoder == null) throw const FormatException('暂时无法解码此图片内容');
  final img.DecodeInfo? info = decoder.startDecode(bytes);
  if (info != null && info.width > 0 && info.height > 0) {
    _validatePixelBudget(info.width, info.height, maxPixels);
  }
  // Only decode the first frame. A few valid static decoders do not implement
  // startDecode, so keep a bounded fallback for those formats.
  final img.Image? decoded = info == null
      ? decoder.decode(bytes, frame: 0)
      : decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('暂时无法解码此图片内容');
  _validatePixelBudget(decoded.width, decoded.height, maxPixels);
  img.Image preview = img.bakeOrientation(decoded);
  final int safeMaxSide = maxSide.clamp(256, 4096);
  if (preview.width > safeMaxSide || preview.height > safeMaxSide) {
    preview = preview.width >= preview.height
        ? img.copyResize(preview, width: safeMaxSide)
        : img.copyResize(preview, height: safeMaxSide);
  }
  return Uint8List.fromList(img.encodePng(preview, level: 3));
}

void _validatePixelBudget(int width, int height, int maxPixels) {
  if (width < 1 || height < 1) {
    throw const FormatException('图片头损坏或尺寸无效');
  }
  if (width > maxPixels || height > maxPixels || width * height > maxPixels) {
    throw FormatException('图片像素 $width×$height 超过安全上限 $maxPixels');
  }
}
