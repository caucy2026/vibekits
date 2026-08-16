import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_whitelist.dart';

void main() {
  test('白名单匹配自身和真实子路径但不匹配相似前缀', () {
    final String root = Directory.systemTemp.absolute.path;

    expect(CleanupWhitelist.contains(root, root), isTrue);
    expect(
      CleanupWhitelist.contains(
        root,
        '$root${Platform.pathSeparator}child${Platform.pathSeparator}a.tmp',
      ),
      isTrue,
    );
    expect(CleanupWhitelist.contains(root, '${root}suffix'), isFalse);
  });

  test('白名单规范化时去空值、去重并忽略大小写', () {
    final String root = Directory.systemTemp.absolute.path;
    final List<String> result = CleanupWhitelist.sanitize(<String>[
      root,
      root.toUpperCase(),
      ' ',
      '$root${Platform.pathSeparator}',
    ]);

    expect(result, hasLength(1));
  });
}
