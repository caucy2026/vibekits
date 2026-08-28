import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_runtime_log_store.dart';

void main() {
  test('运行日志可查询且敏感信息被脱敏', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-harness-logs-',
    );
    addTearDown(() => root.delete(recursive: true));
    HarnessRuntimeLogStore.configure(root.path);

    await HarnessRuntimeLogStore.appendWorkEvent(<String, Object?>{
      'phase': 'failed',
      'message': 'api_key=secret-value timeout',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    final List<HarnessRuntimeLogEntry> logs =
        await HarnessRuntimeLogStore.listLogs();
    final String content = await HarnessRuntimeLogStore.readTail(
      logs.single.path,
    );

    expect(logs.single.name, 'harness-work.jsonl');
    expect(content, contains('timeout'));
    expect(content, isNot(contains('secret-value')));
    expect(content, contains('<hidden>'));
  });
}
