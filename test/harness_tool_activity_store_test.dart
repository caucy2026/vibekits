import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';

void main() {
  test('旧版超长活动摘要在读取时收敛到新上限', () {
    final HarnessToolActivity? entry = HarnessToolActivity.fromJson(
      <String, Object?>{
        'id': 'activity-1',
        'toolId': 'vibekits.mcp.catalog_list',
        'toolName': '目录',
        'target': 'catalog',
        'argumentsSummary': 'a' * 5000,
        'resultSummary': 'r' * 5000,
        'status': 'succeeded',
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'elapsedMs': 10,
      },
    );

    expect(entry, isNotNull);
    expect(entry!.argumentsSummary.length, 1024);
    expect(entry.resultSummary.length, 1024);
    expect(HarnessToolActivityStore.maxEntries, 200);
    expect(HarnessToolActivityStore.targetFileBytes, 512 * 1024);
  });

  test('工具日志默认开启并可只关闭当前模块', () {
    const HarnessToolLoggingPolicy defaults = HarnessToolLoggingPolicy();
    expect(defaults.enabledFor(<String>{'vibekits.file_diff'}), isTrue);

    final HarnessToolLoggingPolicy diffOff = defaults.setEnabled(
      false,
      toolIds: <String>{'vibekits.file_diff'},
    );
    expect(diffOff.enabledFor(<String>{'vibekits.file_diff'}), isFalse);
    expect(diffOff.enabledFor(<String>{'vibekits.adb.command'}), isTrue);

    final HarnessToolLoggingPolicy restored = HarnessToolLoggingPolicy.fromJson(
      diffOff.toJson(),
    ).setEnabled(true, toolIds: <String>{'vibekits.file_diff'});
    expect(restored.enabledFor(<String>{'vibekits.file_diff'}), isTrue);
  });

  test('全局关闭优先于模块默认开启', () {
    const HarnessToolLoggingPolicy disabled = HarnessToolLoggingPolicy(
      globalEnabled: false,
    );
    expect(disabled.enabledFor(<String>{'vibekits.adb.command'}), isFalse);
    expect(disabled.enabledFor(const <String>{}), isFalse);
  });
}
