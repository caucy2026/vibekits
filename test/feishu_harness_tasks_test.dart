import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/feishu_harness_tasks.dart';

void main() {
  test('飞书快捷任务都要求先授权和读取Schema', () {
    expect(FeishuHarnessTasks.quickTasks, hasLength(3));
    for (final FeishuHarnessTask task in FeishuHarnessTasks.quickTasks) {
      expect(task.prompt, contains('vibekits.feishu.auth_status'));
      expect(task.prompt, contains('vibekits.feishu.schema'));
    }
  });

  test('谁在找我任务不会把不存在的历史收件箱能力说成已完成', () {
    final String prompt = FeishuHarnessTasks.whoNeedsMe.prompt;
    expect(prompt, contains('最近24小时'));
    expect(prompt, contains('消息事件订阅'));
    expect(prompt, contains('不得编造联系人或消息'));
    expect(prompt, contains('不发送、修改或删除消息'));
  });
}
