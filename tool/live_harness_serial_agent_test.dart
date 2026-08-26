import 'package:flutter_test/flutter_test.dart';

import 'run_harness_serial_diagnostic.dart' as diagnostic;

void main() {
  test(
    'official Harness autonomously diagnoses the connected serial port',
    diagnostic.main,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
