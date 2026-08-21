import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/git_repository_service.dart';

void main() {
  test('真实 Git 仓库返回根目录、分支、变更、Diff 和日志', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_git_');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    void git(List<String> arguments) {
      final ProcessResult result = Process.runSync(
        GitRepositoryService.bundledExecutable,
        <String>['-C', sandbox.path, ...arguments],
      );
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

  test('内置 Git 对比两个版本并创建不切换的本地分支', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_git_compare_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    String git(List<String> arguments) {
      final ProcessResult result = Process.runSync(
        GitRepositoryService.bundledExecutable,
        <String>['-C', sandbox.path, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}'.trim();
    }

    git(<String>['init']);
    git(<String>['config', 'user.name', 'Vibekits Test']);
    git(<String>['config', 'user.email', 'test@vibekits.local']);
    final File source = File('${sandbox.path}${Platform.pathSeparator}main.txt')
      ..writeAsStringSync('one\n');
    git(<String>['add', 'main.txt']);
    git(<String>['commit', '-m', 'one']);
    final String base = git(<String>['rev-parse', 'HEAD']);
    source.writeAsStringSync('two\n');
    git(<String>['commit', '-am', 'two']);
    final String originalBranch = git(<String>['branch', '--show-current']);

    final GitReferenceComparison comparison =
        await GitRepositoryService.compareRefs(
          sandbox.path,
          baseRef: base,
          targetRef: 'HEAD',
        );
    expect(comparison.changedFiles, contains('main.txt'));
    expect(comparison.diff, contains('+two'));

    final String branch = await GitRepositoryService.createLocalBranch(
      sandbox.path,
      name: 'vibekits/checkpoint',
    );
    expect(branch, 'vibekits/checkpoint');
    expect(git(<String>['branch', '--show-current']), originalBranch);
    expect(
      git(<String>['show-ref', '--verify', 'refs/heads/vibekits/checkpoint']),
      isNotEmpty,
    );
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

  test('备份预览阻断秘密文件且仓库变化使旧计划失效', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_git_backup_secret_',
    );
    final Directory remote = Directory.systemTemp.createTempSync(
      'vk_git_backup_remote_',
    );
    addTearDown(() {
      sandbox.deleteSync(recursive: true);
      remote.deleteSync(recursive: true);
    });

    void run(String directory, List<String> arguments) {
      final ProcessResult result = Process.runSync(
        GitRepositoryService.bundledExecutable,
        <String>['-C', directory, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    run(remote.path, <String>['init', '--bare']);
    run(sandbox.path, <String>['init']);
    run(sandbox.path, <String>['config', 'user.name', 'Vibekits Test']);
    run(sandbox.path, <String>['config', 'user.email', 'test@vibekits.local']);
    File('${sandbox.path}${Platform.pathSeparator}README.md')
        .writeAsStringSync('safe\n');
    run(sandbox.path, <String>['add', 'README.md']);
    run(sandbox.path, <String>['commit', '-m', 'initial']);
    run(sandbox.path, <String>['remote', 'add', 'backup', remote.path]);
    File('${sandbox.path}${Platform.pathSeparator}.env')
        .writeAsStringSync('API_KEY=super-secret-value-12345\n');

    final GitBackupPreview preview = await GitRepositoryService.previewBackup(
      sandbox.path,
      remoteId: 'backup',
      deviceLabel: 'test-device',
      now: DateTime(2026, 8, 21),
    );
    expect(preview.blockers, isNotEmpty);
    expect(preview.includedPaths, contains('.env'));
    expect(preview.targetBranch, startsWith('backup/test-device/'));
    await expectLater(
      GitRepositoryService.commitBackup(
        previewId: preview.id,
        includedPaths: preview.includedPaths,
        message: 'must be blocked',
        now: DateTime(2026, 8, 21, 0, 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('备份 commit 与 push 分离并核对远端 SHA', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_git_backup_',
    );
    final Directory remote = Directory.systemTemp.createTempSync(
      'vk_git_backup_bare_',
    );
    addTearDown(() {
      sandbox.deleteSync(recursive: true);
      remote.deleteSync(recursive: true);
    });

    String run(String directory, List<String> arguments) {
      final ProcessResult result = Process.runSync(
        GitRepositoryService.bundledExecutable,
        <String>['-C', directory, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}'.trim();
    }

    run(remote.path, <String>['init', '--bare']);
    run(sandbox.path, <String>['init']);
    run(sandbox.path, <String>['config', 'user.name', 'Vibekits Test']);
    run(sandbox.path, <String>['config', 'user.email', 'test@vibekits.local']);
    final File source = File('${sandbox.path}${Platform.pathSeparator}main.txt')
      ..writeAsStringSync('one\n');
    run(sandbox.path, <String>['add', 'main.txt']);
    run(sandbox.path, <String>['commit', '-m', 'initial']);
    run(sandbox.path, <String>['remote', 'add', 'backup', remote.path]);
    source.writeAsStringSync('two\n');
    final String originalBranch = run(sandbox.path, <String>[
      'branch',
      '--show-current',
    ]);
    final String originalHead = run(sandbox.path, <String>[
      'rev-parse',
      'HEAD',
    ]);

    final GitBackupPreview preview = await GitRepositoryService.previewBackup(
      sandbox.path,
      remoteId: 'backup',
      deviceLabel: 'qa-machine',
      now: DateTime(2026, 8, 21),
    );
    expect(preview.blockers, isEmpty);
    expect(preview.remoteReachable, isTrue);
    expect(preview.includedPaths, <String>['main.txt']);

    final GitBackupCommitResult committed =
        await GitRepositoryService.commitBackup(
          previewId: preview.id,
          includedPaths: preview.includedPaths,
          message: 'backup test',
          now: DateTime(2026, 8, 21, 0, 1),
        );
    expect(committed.commitSha, hasLength(40));
    expect(
      run(sandbox.path, <String>['branch', '--show-current']),
      originalBranch,
    );
    expect(run(sandbox.path, <String>['rev-parse', 'HEAD']), originalHead);
    expect(source.readAsStringSync(), 'two\n');
    expect(
      run(sandbox.path, <String>['status', '--porcelain']),
      contains('main.txt'),
      reason: '备份提交不能推进当前分支或清空用户工作区',
    );
    expect(
      run(sandbox.path, <String>['ls-remote', '--heads', 'backup']),
      isEmpty,
      reason: 'commit 审批不能隐式执行 push',
    );

    final GitBackupPushResult pushed = await GitRepositoryService.pushBackup(
      previewId: preview.id,
      commitSha: committed.commitSha,
      now: DateTime(2026, 8, 21, 0, 2),
    );
    expect(pushed.verified, isTrue);
    expect(pushed.remoteCommitSha, committed.commitSha);
  });

  test('文件内容变化但 Git 状态路径不变时旧 preview 失效', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_git_backup_race_',
    );
    final Directory remote = Directory.systemTemp.createTempSync(
      'vk_git_backup_race_remote_',
    );
    addTearDown(() {
      sandbox.deleteSync(recursive: true);
      remote.deleteSync(recursive: true);
    });

    void run(String directory, List<String> arguments) {
      final ProcessResult result = Process.runSync(
        GitRepositoryService.bundledExecutable,
        <String>['-C', directory, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    run(remote.path, <String>['init', '--bare']);
    run(sandbox.path, <String>['init']);
    run(sandbox.path, <String>['config', 'user.name', 'Vibekits Test']);
    run(sandbox.path, <String>['config', 'user.email', 'test@vibekits.local']);
    final File source = File(
      '${sandbox.path}${Platform.pathSeparator}settings.txt',
    )..writeAsStringSync('initial\n');
    run(sandbox.path, <String>['add', 'settings.txt']);
    run(sandbox.path, <String>['commit', '-m', 'initial']);
    run(sandbox.path, <String>['remote', 'add', 'backup', remote.path]);
    source.writeAsStringSync('safe change\n');

    final GitBackupPreview preview = await GitRepositoryService.previewBackup(
      sandbox.path,
      remoteId: 'backup',
      now: DateTime(2026, 8, 21),
    );
    expect(preview.blockers, isEmpty);
    source.writeAsStringSync('password=secret-value-injected-after-preview\n');

    await expectLater(
      GitRepositoryService.commitBackup(
        previewId: preview.id,
        includedPaths: preview.includedPaths,
        message: 'must be rejected',
        now: DateTime(2026, 8, 21, 0, 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
