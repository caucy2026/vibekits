import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_diff_service.dart';

void main() {
  test('比较两个真实文本文件并返回行号、统计和统一 Diff', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_file_diff_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File left = File('${sandbox.path}/left.txt')
      ..writeAsStringSync('one\nold\nshared\n');
    final File right = File('${sandbox.path}/right.txt')
      ..writeAsStringSync('one\nnew\nshared\nextra\n');

    final FileDiffResult result = await FileDiffService.compare(
      leftPath: left.path,
      rightPath: right.path,
    );

    expect(result.identical, isFalse);
    expect(result.addedLines, 2);
    expect(result.removedLines, 1);
    expect(result.unchangedLines, 2);
    expect(result.exactMinimalDiff, isTrue);
    expect(result.unifiedText, contains('-old'));
    expect(result.unifiedText, contains('+new'));
    expect(
      result.lines
          .singleWhere((FileDiffLine line) => line.text == 'extra')
          .rightLine,
      4,
    );
  });

  test('忽略空白和大小写后内容可判定相同', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_file_diff_options_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File left = File('${sandbox.path}/left.txt')
      ..writeAsStringSync('Hello    World\n');
    final File right = File('${sandbox.path}/right.txt')
      ..writeAsStringSync('hello world\n');

    final FileDiffResult result = FileDiffService.compareSync(
      leftPath: left.path,
      rightPath: right.path,
      ignoreWhitespace: true,
      ignoreCase: true,
    );

    expect(result.identical, isTrue);
    expect(result.unchangedLines, 1);
  });

  test('大规模完全不同文件使用有界块比较而不产生二次方内存', () {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_file_diff_bounded_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File left = File('${sandbox.path}/left.txt')
      ..writeAsStringSync(
        List<String>.generate(2100, (int i) => 'left-$i').join('\n'),
      );
    final File right = File('${sandbox.path}/right.txt')
      ..writeAsStringSync(
        List<String>.generate(2100, (int i) => 'right-$i').join('\n'),
      );

    final FileDiffResult result = FileDiffService.compareSync(
      leftPath: left.path,
      rightPath: right.path,
    );

    expect(result.exactMinimalDiff, isFalse);
    expect(result.removedLines, 2100);
    expect(result.addedLines, 2100);
  });
}
