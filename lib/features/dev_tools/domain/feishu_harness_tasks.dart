class FeishuHarnessTask {
  const FeishuHarnessTask({
    required this.id,
    required this.label,
    required this.prompt,
  });

  final String id;
  final String label;
  final String prompt;
}

abstract final class FeishuHarnessTasks {
  static const FeishuHarnessTask whoNeedsMe = FeishuHarnessTask(
    id: 'who-needs-me',
    label: '看看谁在找我',
    prompt: '帮我查看飞书上谁在找我。先调用 vibekits.feishu.auth_status；未授权时只说明完成官方配置/OAuth所需步骤。已授权后先调用 vibekits.feishu.schema 核对只读消息或会话接口，只汇总最近24小时的发送人、时间、提及我的上下文和待回复事项，不发送、修改或删除消息。如果官方API不提供历史收件箱读取且本地没有消息事件归档，明确说明需要配置飞书消息事件订阅，不得编造联系人或消息。',
  );

  static const FeishuHarnessTask todaySchedule = FeishuHarnessTask(
    id: 'today-schedule',
    label: '汇总今天日程',
    prompt: '帮我汇总今天的飞书日程。依次调用 vibekits.feishu.auth_status、vibekits.feishu.schema，再用 vibekits.feishu.execute 执行Schema确认过的只读日历命令；按时间列出主题、参与人、地点和冲突。未授权或scope不足时说明缺失项，不得创建或修改日程。',
  );

  static const FeishuHarnessTask pendingTasks = FeishuHarnessTask(
    id: 'pending-tasks',
    label: '整理待办事项',
    prompt: '帮我整理飞书待办。依次调用 vibekits.feishu.auth_status、vibekits.feishu.schema，再用 vibekits.feishu.execute 读取Schema确认过的只读任务接口；按逾期、今天、本周分组并标明负责人。未授权或scope不足时说明缺失项，不得完成、修改或删除任务。',
  );

  static const List<FeishuHarnessTask> quickTasks = <FeishuHarnessTask>[
    whoNeedsMe,
    todaySchedule,
    pendingTasks,
  ];
}
