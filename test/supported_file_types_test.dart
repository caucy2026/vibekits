import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/supported_file_types.dart';

void main() {
  test('只把真实支持的压缩格式路由到解压模块', () {
    for (final String extension in SupportedFileTypes.archiveExtensions) {
      expect(
        SupportedFileTypes.kindForPath('sample.$extension'),
        VibekitsFileKind.archive,
      );
    }
    expect(
      SupportedFileTypes.kindForPath('unsupported.rar'),
      VibekitsFileKind.unsupported,
    );
    expect(
      SupportedFileTypes.kindForPath('unsupported.iso'),
      VibekitsFileKind.unsupported,
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
}
