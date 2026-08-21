import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_test_node_service.dart';

void main() {
  test('Windows 本机只读探测能返回结构化检查且不执行变更', () async {
    if (!Platform.isWindows) return;
    final WindowsNodeInspection inspection = await WindowsTestNodeService()
        .inspect();
    expect(inspection.rootPath, WindowsTestNodeService.requiredRoot);
    expect(inspection.checks, isNotEmpty);
    expect(
      inspection.checks.map((WindowsNodeCheck item) => item.id),
      containsAll(<String>[
        'windows_support',
        'hardware',
        'd_drive',
        'openssh',
      ]),
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}
