import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/supported_file_types.dart';
import 'package:vibekits/features/about/domain/about_capability_manifest.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';

void main() {
  test('about inventory stays synchronized with runtime registries', () {
    expect(
      AboutCapabilityManifest.supportedExtensionCount,
      SupportedFileTypes.allExtensions.toSet().length,
    );
    expect(AboutCapabilityManifest.toolCount, allDevToolRegistry.length);
    expect(
      AboutCapabilityManifest.independentWorkspaceCount,
      devToolRegistry.length,
    );
    expect(
      AboutCapabilityManifest.toolGroups
          .expand((group) => group.tools)
          .map((tool) => tool.id),
      contains('network_speed'),
    );
  });

  test('about page truthfully explains portable VibeKits data', () {
    final AboutFormatGroup group = AboutCapabilityManifest.formatGroups
        .singleWhere((item) => item.title == 'VibeKits 自有数据与协议');
    expect(group.description, contains('不发明私有文档后缀'));
    expect(group.values, containsAll(<String>['JSON', 'LMCP/2', 'MCP']));
  });
}
