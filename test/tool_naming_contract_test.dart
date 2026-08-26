import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

void main() {
  test('独立工具统一使用中文用途加标准英文名', () {
    final RegExp chinese = RegExp(r'[\u4e00-\u9fff]');
    final RegExp bilingual = RegExp(r'^.+（[^（）]+）$');

    for (final ToolSpec tool in devToolRegistry) {
      expect(
        chinese.hasMatch(tool.name),
        isTrue,
        reason: '${tool.id} 缺少中文用途名称：${tool.name}',
      );
      expect(
        bilingual.hasMatch(tool.name),
        isTrue,
        reason: '${tool.id} 应使用“中文（标准名）”：${tool.name}',
      );
    }
  });
}
