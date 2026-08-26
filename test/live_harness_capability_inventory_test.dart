import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/run_harness_capability_inventory.dart' as inventory;

void main() {
  test(
    'official Harness reports VibeKits capability count and invocation contract',
    inventory.main,
    timeout: const Timeout(Duration(minutes: 4)),
    skip: Platform.environment['VIBEKITS_RUN_LIVE_HARNESS_CAPABILITY'] == '1'
        ? false
        : '仅在显式授权真实模型联网验收时运行',
  );
}
