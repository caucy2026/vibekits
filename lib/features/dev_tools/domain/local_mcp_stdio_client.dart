import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalMcpException implements Exception {
  const LocalMcpException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class LocalMcpStdioClient {
  const LocalMcpStdioClient({
    this.startTimeout = const Duration(seconds: 8),
    this.callTimeout = const Duration(seconds: 120),
  });

  final Duration startTimeout;
  final Duration callTimeout;

  Future<Map<String, Object?>> callTool({
    required String executable,
    List<String> launchArguments = const <String>[],
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    Map<String, Object?>? scheduling,
  }) async {
    final File file = File(executable);
    if (!file.isAbsolute || !await file.exists()) {
      throw const LocalMcpException(
        'invalid_executable',
        '本地 MCP executable 必须是存在的绝对文件路径',
      );
    }
    final Process process;
    try {
      process = await Process.start(
        file.absolute.path,
        List<String>.unmodifiable(launchArguments),
        mode: ProcessStartMode.normal,
        runInShell: false,
      ).timeout(startTimeout);
    } on Object catch (error) {
      throw LocalMcpException('start_failed', '本地 MCP 启动失败：$error');
    }
    final StreamIterator<String> stdout = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final List<String> stderrTail = <String>[];
    final StreamSubscription<String> stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          if (stderrTail.length == 10) stderrTail.removeAt(0);
          stderrTail.add(_bounded(line, 300));
        });
    try {
      await _send(process, <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'VibeKits',
            'version': '1.9.0',
          },
        },
      });
      await _response(stdout, 1, startTimeout);
      await _send(process, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      await _send(process, <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': <String, Object?>{},
      });
      final Map<String, Object?> catalog = await _response(
        stdout,
        2,
        startTimeout,
      );
      final Object? rawTools = catalog['tools'];
      if (rawTools is! List ||
          !rawTools.whereType<Map>().any(
            (Map tool) => '${tool['name'] ?? ''}' == toolName,
          )) {
        throw const LocalMcpException(
          'tool_not_in_live_catalog',
          '请求工具未出现在本地进程的实时 tools/list 中',
        );
      }
      await _send(process, <String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': toolName,
          'arguments': arguments,
          'scheduling': ?scheduling,
        },
      });
      return await _response(stdout, 3, callTimeout);
    } on TimeoutException {
      throw const LocalMcpException('timeout', '本地 MCP 调用超时');
    } on LocalMcpException {
      rethrow;
    } on Object catch (error) {
      throw LocalMcpException(
        'protocol_error',
        '本地 MCP 协议错误：${_bounded('$error', 500)}',
      );
    } finally {
      await stdout.cancel();
      await stderrSubscription.cancel();
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  static Future<void> _send(
    Process process,
    Map<String, Object?> message,
  ) async {
    process.stdin.writeln(jsonEncode(message));
    await process.stdin.flush();
  }

  static Future<Map<String, Object?>> _response(
    StreamIterator<String> stdout,
    int id,
    Duration timeout,
  ) async {
    while (await stdout.moveNext().timeout(timeout)) {
      final String line = stdout.current.trim();
      if (line.isEmpty || line.length > 4 * 1024 * 1024) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map || decoded['id'] != id) continue;
      if (decoded['error'] is Map) {
        final Map error = decoded['error']! as Map;
        throw LocalMcpException(
          'remote_error',
          _bounded('${error['message'] ?? '本地 MCP 返回错误'}', 500),
        );
      }
      final Object? result = decoded['result'];
      if (result is! Map) {
        throw const LocalMcpException(
          'invalid_response',
          '本地 MCP 响应缺少 result 对象',
        );
      }
      return Map<String, Object?>.from(result);
    }
    throw const LocalMcpException('closed', '本地 MCP 在响应前退出');
  }

  static String _bounded(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
