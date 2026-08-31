import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/git_repository_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('Git 工作区一次选择后展示变更、Diff 和日志', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int inspections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            gitPickDirectory: () async => r'D:\project',
            gitInspect: (String path) async {
              inspections++;
              return const GitRepositorySnapshot(
                root: r'D:\project',
                branch: 'main...origin/main',
                status: ' M lib/main.dart',
                diff: '-old\n+new',
                log: 'abc123\t2026-08-16\tupdate',
              );
            },
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '版本控制');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev-tool-nav-git_workspace')));
    await tester.pump();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(inspections, 1);
    expect(find.textContaining('lib/main.dart'), findsOneWidget);

    await tester.tap(find.text('Diff'));
    await tester.pump();
    expect(find.textContaining('-old'), findsOneWidget);
    await tester.tap(find.text('日志'));
    await tester.pump();
    expect(find.textContaining('update'), findsOneWidget);
  });

  testWidgets('安全备份先预览并分别确认 commit 和 push', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int commits = 0;
    int pushes = 0;
    final DateTime expiresAt = DateTime(2026, 8, 21, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            gitPickDirectory: () async => r'D:\project',
            gitInspect: (_) async => const GitRepositorySnapshot(
              root: r'D:\project',
              branch: 'main',
              status: ' M lib/main.dart',
              diff: '-old\n+new',
              log: 'abc update',
            ),
            gitBackupPreview: (String path, String remote) async =>
                GitBackupPreview(
                  id: 'preview-1',
                  repositoryRoot: path,
                  repositoryStateDigest: 'digest',
                  currentBranch: 'main',
                  remoteId: remote,
                  remoteUrl: 'ssh://github.example/repo.git',
                  targetBranch: 'backup/test/project/20260821',
                  includedPaths: const <String>['lib/main.dart'],
                  stagedCount: 0,
                  unstagedCount: 1,
                  untrackedCount: 0,
                  blockers: const <String>[],
                  warnings: const <String>[],
                  remoteReachable: true,
                  expiresAt: expiresAt,
                ),
            gitBackupCommit:
                (String previewId, List<String> paths, String message) async {
                  commits++;
                  expect(previewId, 'preview-1');
                  expect(paths, <String>['lib/main.dart']);
                  return const GitBackupCommitResult(
                    previewId: 'preview-1',
                    commitSha: '1111111111111111111111111111111111111111',
                    targetBranch: 'backup/test/project/20260821',
                    pathCount: 1,
                  );
                },
            gitBackupPush: (String previewId, String sha) async {
              pushes++;
              return const GitBackupPushResult(
                previewId: 'preview-1',
                remoteId: 'backup',
                targetBranch: 'backup/test/project/20260821',
                localCommitSha: '1111111111111111111111111111111111111111',
                remoteCommitSha: '1111111111111111111111111111111111111111',
                verified: true,
              );
            },
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, '版本控制');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev-tool-nav-git_workspace')));
    await tester.pump();
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('安全备份'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('git-backup-preview')));
    await tester.pumpAndSettle();
    expect(find.text('lib/main.dart'), findsOneWidget);

    await tester.tap(find.byKey(const Key('git-backup-commit')));
    await tester.pumpAndSettle();
    expect(commits, 0);
    expect(pushes, 0);
    await tester.tap(find.byKey(const Key('git-backup-confirm-commit')));
    await tester.pumpAndSettle();
    expect(commits, 1);
    expect(pushes, 0, reason: 'commit 审批不能自动放行 push');

    await tester.tap(find.byKey(const Key('git-backup-push')));
    await tester.pumpAndSettle();
    expect(pushes, 0);
    await tester.tap(find.byKey(const Key('git-backup-confirm-push')));
    await tester.pumpAndSettle();
    expect(pushes, 1);
    expect(find.textContaining('远端 commit'), findsOneWidget);
    expect(find.textContaining('一致'), findsOneWidget);
  });
}
