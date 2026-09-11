import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/supported_file_types.dart';

void main() {
  test('macOS 注册全部真实支持格式并使用优先处理等级', () {
    final File infoPlist = File('macos/Runner/Info.plist');
    expect(infoPlist.existsSync(), isTrue);
    final String source = infoPlist.readAsStringSync();

    for (final String extension in SupportedFileTypes.allExtensions) {
      expect(
        source,
        contains('<string>$extension</string>'),
        reason: 'macOS 打开方式遗漏 .$extension',
      );
    }
    expect(
      RegExp(r'<key>LSHandlerRank</key>\s*<string>Owner</string>')
          .allMatches(source)
          .length,
      6,
    );
    expect(source, isNot(contains('<string>public.data</string>')));
  });
}
