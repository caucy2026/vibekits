import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'tool_result.dart';

abstract final class MicroBenchmarkService {
  static Future<ToolResult> run(String input, String params) =>
      Isolate.run<ToolResult>(
        () => _runSync(input, params),
        debugName: 'vibekits-safe-benchmark',
      );

  static ToolResult _runSync(String input, String params) {
    if (utf8.encode(input).length > 1024 * 1024) {
      return const ToolFailure('基准输入最多 1 MiB');
    }
    final List<String> parts = params.split('|');
    final String operation = parts.first.trim().isEmpty
        ? 'sha256'
        : parts.first.trim().toLowerCase();
    final int iterations =
        (parts.length > 1 ? int.tryParse(parts[1]) : null) ?? 30;
    if (!const <String>{'sha256', 'json_parse', 'base64'}.contains(operation)) {
      return const ToolFailure('操作只能是 sha256/json_parse/base64');
    }
    if (iterations < 5 || iterations > 200) {
      return const ToolFailure('迭代次数必须在 5～200 之间');
    }
    Object? execute() => switch (operation) {
      'sha256' => sha256.convert(utf8.encode(input)).bytes.first,
      'json_parse' => jsonDecode(input),
      'base64' => base64Encode(utf8.encode(input)),
      _ => null,
    };
    try {
      for (int index = 0; index < 3; index++) {
        execute();
      }
      final List<int> samples = <int>[];
      Object? last;
      for (int index = 0; index < iterations; index++) {
        final Stopwatch watch = Stopwatch()..start();
        last = execute();
        watch.stop();
        samples.add(max(1, watch.elapsedMicroseconds));
      }
      samples.sort();
      final double mean =
          samples.reduce((int a, int b) => a + b) / samples.length;
      int percentile(double value) =>
          samples[((samples.length - 1) * value).round().clamp(
            0,
            samples.length - 1,
          )];
      return ToolSuccess(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'operation': operation,
          'iterations': iterations,
          'warmupIterations': 3,
          'unit': 'microseconds',
          'min': samples.first,
          'mean': double.parse(mean.toStringAsFixed(2)),
          'p50': percentile(0.50),
          'p95': percentile(0.95),
          'max': samples.last,
          'resultType': last.runtimeType.toString(),
          'note': '同机相对比较有效；后台负载、缓存和电源策略会影响结果。',
        }),
      );
    } on FormatException catch (error) {
      return ToolFailure('基准输入无效：${error.message}');
    }
  }
}
