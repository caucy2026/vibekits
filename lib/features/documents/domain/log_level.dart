/// 日志等级着色分类（docs/00 §5.3，DOC-103）。
enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
  plain;

  static LogLevel of(String line) {
    final String upper = line.toUpperCase();
    if (upper.contains('ERROR') || upper.contains('FATAL')) {
      return LogLevel.error;
    }
    if (upper.contains('WARN')) {
      return LogLevel.warn;
    }
    if (upper.contains('DEBUG')) {
      return LogLevel.debug;
    }
    if (upper.contains('TRACE')) {
      return LogLevel.trace;
    }
    if (upper.contains('INFO')) {
      return LogLevel.info;
    }
    return LogLevel.plain;
  }
}
