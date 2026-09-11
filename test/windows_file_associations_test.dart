import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 文件关联复用统一格式清单并保留六类入口', () {
    final String source = File(
      'lib/app/windows_file_associations.dart',
    ).readAsStringSync();

    expect(source, contains('SupportedFileTypes.allExtensions'));
    expect(source, contains("archiveProgId = 'Vibekits.Archive'"));
    expect(source, contains("documentProgId = 'Vibekits.Document'"));
    expect(source, contains("imageProgId = 'Vibekits.Image'"));
    expect(source, contains("databaseProgId = 'Vibekits.Database'"));
    expect(source, contains("modelProgId = 'Vibekits.Model'"));
    expect(source, contains("audioProgId = 'Vibekits.Audio'"));
    expect(source, contains('用 Vibekits 分析音频'));
  });
}
