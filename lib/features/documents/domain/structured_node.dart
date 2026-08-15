/// 结构化树节点（JSON/XML 共用）。
class StructuredNode {
  const StructuredNode({
    required this.label,
    this.value,
    this.children = const <StructuredNode>[],
  });

  /// 键名或标签名。
  final String label;

  /// 标量值或对象/数组的摘要（如 `{3}`、`[10]`）。
  final String? value;

  final List<StructuredNode> children;

  bool get isLeaf => children.isEmpty;
}
