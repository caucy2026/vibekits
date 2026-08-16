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

  test('批量重命名检查冲突与 Windows 非法名称', () {
    final Directory tmp = Directory.systemTemp.createTempSync(
      'vk_rename_check',
    );
    File('${tmp.path}/a.txt').writeAsStringSync('a');
    File('${tmp.path}/b.txt').writeAsStringSync('b');
    try {
      final BatchRenamePlan conflict = FileTools.buildBatchRenamePlan(
        tmp.path,
        const BatchRenameOptions(find: 'a', replace: 'b'),
      );
      expect(conflict.canExecute, isFalse);
      expect(conflict.issueCount, 1);
      expect(conflict.items.first.issue, contains('相同名称'));

      final BatchRenamePlan invalid = FileTools.buildBatchRenamePlan(
        tmp.path,
        const BatchRenameOptions(find: 'a', replace: 'CON'),
      );
      expect(invalid.canExecute, isFalse);
      expect(invalid.items.first.issue, contains('保留名称'));
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('批量重命名真实执行并保留扩展名和内容', () {
    final Directory tmp = Directory.systemTemp.createTempSync('vk_rename_run');
    File('${tmp.path}/alpha.txt').writeAsStringSync('alpha-content');
    File('${tmp.path}/beta.log').writeAsStringSync('beta-content');
    try {
      final BatchRenamePlan plan = FileTools.buildBatchRenamePlan(
        tmp.path,
        const BatchRenameOptions(
          prefix: 'src_',
          suffix: '_',
          addSequence: true,
          sequenceStart: 7,
          sequencePadding: 3,
        ),
      );
      expect(plan.canExecute, isTrue);
      expect(plan.items[0].newName, 'src_alpha_007.txt');
      expect(plan.items[1].newName, 'src_beta_008.log');

      final BatchRenameReport report = FileTools.executeBatchRename(plan);
      expect(report.isSuccess, isTrue);
      expect(File('${tmp.path}/alpha.txt').existsSync(), isFalse);
      expect(
        File('${tmp.path}/src_alpha_007.txt').readAsStringSync(),
        'alpha-content',
      );
      expect(
        File('${tmp.path}/src_beta_008.log').readAsStringSync(),
        'beta-content',
      );
      expect(
        tmp.listSync().where(
          (FileSystemEntity entity) =>
              entity.path.contains('.vibekits-rename-'),
        ),
        isEmpty,
      );
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('批量重命名中途失败会恢复已暂存文件', () {
    final Directory tmp = Directory.systemTemp.createTempSync(
      'vk_rename_rollback',
    );
    final File source = File('${tmp.path}/safe.txt')..writeAsStringSync('safe');
    final String missing = '${tmp.path}/missing.txt';
    try {
      final BatchRenamePlan injectedFailure = BatchRenamePlan(
        directory: tmp.path,
        items: <BatchRenameItem>[
          BatchRenameItem(
            sourcePath: source.path,
            oldName: 'safe.txt',
            newName: 'renamed.txt',
          ),
          BatchRenameItem(
            sourcePath: missing,
            oldName: 'missing.txt',
            newName: 'never.txt',
          ),
        ],
      );
      final BatchRenameReport report = FileTools.executeBatchRename(
        injectedFailure,
      );
      expect(report.isSuccess, isFalse);
      expect(source.readAsStringSync(), 'safe');
      expect(File('${tmp.path}/renamed.txt').existsSync(), isFalse);
      expect(
        tmp.listSync().where(
          (FileSystemEntity entity) => entity.path.contains('.vibekits-'),
        ),
        isEmpty,
      );
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
