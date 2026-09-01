import 'package:flutter_test/flutter_test.dart';

import '../tool/adb_readonly_acceptance.dart' as acceptance;

void main() {
  const String adb = String.fromEnvironment('VIBEKITS_LIVE_ADB_EXECUTABLE');
  const String target = String.fromEnvironment('VIBEKITS_LIVE_ADB_TARGET');
  test(
    '真实设备通过 Harness 工具桥读取多项属性和双屏显示状态',
    () => acceptance.main(<String>[adb, target]),
    skip: adb.isEmpty || target.isEmpty
        ? '需要指定 VIBEKITS_LIVE_ADB_EXECUTABLE 和 VIBEKITS_LIVE_ADB_TARGET'
        : false,
  );
}
