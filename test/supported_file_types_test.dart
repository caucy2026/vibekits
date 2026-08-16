import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/supported_file_types.dart';

void main() {
  test('内置 7-Zip 与纯 Dart 后端支持的压缩格式都路由到解压模块', () {
    for (final String extension in SupportedFileTypes.archiveExtensions) {
      expect(
        SupportedFileTypes.kindForPath('sample.$extension'),
        VibekitsFileKind.archive,
      );
    }
    expect(
      SupportedFileTypes.kindForPath('sample.rar'),
      VibekitsFileKind.archive,
    );
    expect(
      SupportedFileTypes.kindForPath('sample.iso'),
      VibekitsFileKind.archive,
    );
    expect(
      SupportedFileTypes.kindForPath('sample.zst'),
      VibekitsFileKind.archive,
    );
  });

  test('常见源码配置和多媒体文档路由到文档解码', () {
    for (final String path in <String>[
      'main.dart',
      'app.tsx',
      'script.ps1',
      'query.sql',
      'settings.yaml',
      '.gitignore',
      'Dockerfile',
      'book.epub',
      'data.bin',
    ]) {
      expect(
        SupportedFileTypes.kindForPath(path),
        VibekitsFileKind.document,
        reason: path,
      );
    }
  });

  test('文件关联扩展名没有重复', () {
    expect(
      SupportedFileTypes.allExtensions.toSet().length,
      SupportedFileTypes.allExtensions.length,
    );
  });

  test('未知扩展名留给内容路由层处理', () {
    expect(
      SupportedFileTypes.kindForPath('unknown.xyz'),
      VibekitsFileKind.unsupported,
    );
  });

  test('常见本地模型格式路由到模型仓库', () {
    for (final String extension in <String>[
      'onnx',
      'ort',
      'tflite',
      'gguf',
      'model',
    ]) {
      expect(
        SupportedFileTypes.kindForPath('model.$extension'),
        VibekitsFileKind.model,
      );
    }
  });

  test('主流和开发图片格式路由到图片预览与 OCR', () {
    for (final String extension in <String>[
      'png',
      'jpg',
      'webp',
      'gif',
      'tiff',
      'ico',
      'psd',
      'exr',
    ]) {
      expect(
        SupportedFileTypes.kindForPath('image.$extension'),
        VibekitsFileKind.image,
        reason: extension,
      );
    }
  });

  test('SQLite 数据库扩展名路由到数据库管理器', () {
    for (final String extension in SupportedFileTypes.databaseExtensions) {
      expect(
        SupportedFileTypes.kindForPath('data.$extension'),
        VibekitsFileKind.database,
      );
    }
  });
}
