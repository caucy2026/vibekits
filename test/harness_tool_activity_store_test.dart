import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';

void main() {
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
