import 'package:flutter_test/flutter_test.dart';

import '../tool/adb_semantic_acceptance.dart' as acceptance;

void main() {
  const String target = String.fromEnvironment('VIBEKITS_LIVE_ADB_TARGET');
  const String apk = String.fromEnvironment('VIBEKITS_LIVE_ADB_APK');
  test(
    '真实设备通过 Harness 语义工具完成 Shell/Logcat/推拉文件/截图',
    () => acceptance.main(<String>[target, if (apk.isNotEmpty) apk]),
    skip: target.isEmpty
        ? '需要 --dart-define=VIBEKITS_LIVE_ADB_TARGET=host:port'
        : false,
  );
}
