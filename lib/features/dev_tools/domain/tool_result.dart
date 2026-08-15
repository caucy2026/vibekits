/// 开发工具的运行结果。
///
/// 纯 Dart，不依赖 Flutter，便于快速单元测试。
sealed class ToolResult {
  const ToolResult();
}

/// 成功结果，携带输出文本。
class ToolSuccess extends ToolResult {
  const ToolSuccess(this.output);

  final String output;
}

/// 失败结果，携带可读原因；[position] 在可确定时给出出错位置（0 基）。
class ToolFailure extends ToolResult {
  const ToolFailure(this.message, {this.position});

  final String message;
  final int? position;
}
