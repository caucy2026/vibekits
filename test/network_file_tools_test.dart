import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/file_tools.dart';
import 'package:vibekits/features/dev_tools/domain/network_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('URL 分解', () {
    final String out = (NetworkTools.urlParse(
      'https://a.com:8080/p?q=1',
    ) as ToolSuccess).output;
    expect(out, contains('scheme: https'));
    expect(out, contains('host: a.com'));
    expect(out, contains('port: 8080'));
  });

  test('CIDR 计算', () {
    final String out =
        (NetworkTools.cidrCalc('192.168.1.0/24') as ToolSuccess).output;
    expect(out, contains('192.168.1.0/24'));
    expect(out, contains('192.168.1.255'));
    expect(out, contains('256'));
  });

  test('非法 CIDR 失败', () {
    expect(NetworkTools.cidrCalc('abc'), isA<ToolFailure>());
  });

  test('文件哈希', () {
    final Directory tmp = Directory.systemTemp.createTempSync('vk_hash');
    final File file = File('${tmp.path}/a.txt')..writeAsStringSync('hello');
    try {
      final String out =
          (FileTools.fileHash(file.path, 'sha256') as ToolSuccess).output;
      expect(out.length, 64);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('批量重命名计划', () {
    final Directory tmp = Directory.systemTemp.createTempSync('vk_rename');
    File('${tmp.path}/a.txt').writeAsStringSync('');
    File('${tmp.path}/b.txt').writeAsStringSync('');
    try {
      final String out = (FileTools.batchRenamePlan(
        tmp.path,
        '.txt',
        '.md',
      ) as ToolSuccess).output;
      expect(out, contains('a.txt -> a.md'));
      expect(out, contains('b.txt -> b.md'));
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
