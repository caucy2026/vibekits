import 'package:xml/xml.dart';

import 'structured_node.dart';

/// 将 XML 构建为树（docs/00 §5.3，DOC-106）。
///
/// 禁用 DTD 与外部实体；深度上限 128。
const int kMaxXmlDepth = 128;

StructuredNode buildXmlTree(String source) {
  final XmlDocument document = XmlDocument.parse(source);
  final XmlElement root = document.rootElement;
  return _fromElement(root, 0);
}

StructuredNode _fromElement(XmlElement element, int depth) {
  if (depth > kMaxXmlDepth) {
    throw const FormatException('XML 嵌套深度超过 $kMaxXmlDepth');
  }
  final List<StructuredNode> children = <StructuredNode>[];

  // 属性作为叶子节点，标签以 @ 前缀。
  for (final XmlAttribute attr in element.attributes) {
    children.add(
      StructuredNode(label: '@${attr.name.local}', value: attr.value),
    );
  }

  for (final XmlNode node in element.children) {
    if (node is XmlElement) {
      children.add(_fromElement(node, depth + 1));
    } else if (node is XmlText) {
      final String text = node.value.trim();
      if (text.isNotEmpty) {
        children.add(StructuredNode(label: '#text', value: text));
      }
    }
  }

  final String summary = children.isEmpty ? '' : '${children.length}';
  return StructuredNode(
    label: element.name.local,
    value: summary,
    children: children,
  );
}
