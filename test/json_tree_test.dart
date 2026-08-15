import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/json_tree.dart';

void main() {
  test('对象与数组树', () {
    final Object? value = jsonDecode(
      '{"a": 1, "b": [true, null], "c": {"d": "x"}}',
    );
    final root = buildJsonTree(value, 'root');
    expect(root.label, 'root');
    expect(root.value, '{3}');
    expect(root.children.length, 3);
    expect(root.children[0].label, 'a');
    expect(root.children[0].value, '1');
    expect(root.children[1].value, '[2]');
    expect(root.children[1].children[0].value, 'true');
    expect(root.children[1].children[1].value, 'null');
  });

  test('字符串标量带引号', () {
    final root = buildJsonTree('hi', 'k');
    expect(root.value, '"hi"');
  });

  test('超过最大深度抛错', () {
    Object? value = <Object?, Object?>{};
    for (int i = 0; i < 130; i++) {
      value = <Object?, Object?>{'n': value};
    }
    expect(() => buildJsonTree(value, 'root'), throwsFormatException);
  });
}
