import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/git_repository_service.dart';

void main() {
  test('真实 Git 仓库返回根目录、分支、变更、Diff 和日志', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_git_');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    void git(List<String> arguments) {
      final ProcessResult result = Process.runSync('git', <String>[
        '-C',
        sandbox.path,
        ...arguments,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    git(<String>['init']);
    git(<String>['config', 'user.name', 'Vibekits Test']);
    git(<String>['config', 'user.email', 'test@vibekits.local']);
    final File source = File('${sandbox.path}${Platform.pathSeparator}main.txt')
      ..writeAsStringSync('before\n');
    git(<String>['add', 'main.txt']);
    git(<String>['commit', '-m', 'initial']);
    source.writeAsStringSync('after\n');

    final GitRepositorySnapshot snapshot = await GitRepositoryService.inspect(
      sandbox.path,
    );
    expect(
      File(snapshot.root).absolute.path.replaceAll('\\', '/'),
      sandbox.absolute.path.replaceAll('\\', '/'),
    );
    expect(snapshot.branch, isNotEmpty);
    expect(snapshot.status, contains('main.txt'));
    expect(snapshot.diff, contains('-before'));
    expect(snapshot.diff, contains('+after'));
    expect(snapshot.log, contains('initial'));
  });

  test('非仓库目录返回 Git 的明确错误', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_not_git_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    await expectLater(
      GitRepositoryService.inspect(sandbox.path),
      throwsA(isA<FormatException>()),
    );
  });
}
