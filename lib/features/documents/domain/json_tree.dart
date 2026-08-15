import 'structured_node.dart';

/// 将 JSON 值构建为树（docs/00 §5.3，DOC-106）。
///
/// 最大深度 128，超过时抛出 [FormatException]，由调用方回退源码。
const int kMaxJsonDepth = 128;

StructuredNode buildJsonTree(Object? value, String label, {int depth = 0}) {
  if (depth > kMaxJsonDepth) {
    throw const FormatException('JSON 嵌套深度超过 $kMaxJsonDepth');
  }
  if (value is Map) {
    final List<StructuredNode> children = value.entries
        .map(
          (MapEntry<Object?, Object?> e) =>
              buildJsonTree(e.value, '${e.key}', depth: depth + 1),
        )
        .toList();
    return StructuredNode(
      label: label,
      value: '{${value.length}}',
      children: children,
    );
  }
  if (value is List) {
    final List<StructuredNode> children = List<StructuredNode>.generate(
      value.length,
      (int i) => buildJsonTree(value[i], '[$i]', depth: depth + 1),
    );
    return StructuredNode(
      label: label,
      value: '[${value.length}]',
      children: children,
    );
  }
  return StructuredNode(label: label, value: _scalarText(value));
}

String _scalarText(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return '"$value"';
  }
  return value.toString();
}
