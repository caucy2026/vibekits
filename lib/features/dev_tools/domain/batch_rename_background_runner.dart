import 'dart:isolate';

import 'file_tools.dart';

/// 批量重命名的目录枚举、冲突规划和实际文件操作均不占用 UI Isolate。
abstract final class BatchRenameBackgroundRunner {
  static Future<BatchRenamePlan> buildPlan(
    String directory,
    BatchRenameOptions options,
  ) => Isolate.run(
    () => FileTools.buildBatchRenamePlan(directory, options),
    debugName: 'vibekits-rename-plan',
  );

  static Future<BatchRenameReport> execute(BatchRenamePlan plan) => Isolate.run(
    () => FileTools.executeBatchRename(plan),
    debugName: 'vibekits-rename-execute',
  );
}
