import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/micro_benchmark_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('受限基准执行预热、多轮统计且不接受任意命令', () async {
    final ToolResult result = await MicroBenchmarkService.run(
      '{"value":1}',
      'json_parse|8',
    );
    final Map<String, Object?> report =
        jsonDecode((result as ToolSuccess).output) as Map<String, Object?>;
    expect(report['iterations'], 8);
    expect(report['warmupIterations'], 3);
    expect(report['p95'], isA<int>());

    final ToolResult rejected = await MicroBenchmarkService.run(
      'echo unsafe',
      'powershell|10',
    );
    expect(rejected, isA<ToolFailure>());
  });
}
