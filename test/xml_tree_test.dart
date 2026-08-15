import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/xml_tree.dart';

void main() {
  test('元素、属性与文本', () {
    const String xml =
        '<?xml version="1.0"?><root id="1"><name>Vibekits</name><tags><t>a</t><t>b</t></tags></root>';
    final root = buildXmlTree(xml);
    expect(root.label, 'root');
    // 属性 @id + 子元素 name、tags
    expect(root.children.length, 3);
    expect(root.children[0].label, '@id');
    expect(root.children[0].value, '1');
    expect(root.children[1].label, 'name');
    expect(root.children[1].children.single.value, 'Vibekits');
  });

  test('非法 XML 抛错', () {
    expect(() => buildXmlTree('<a><b></a>'), throwsA(anything));
  });
}
