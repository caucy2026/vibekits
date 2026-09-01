import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_background_runner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_platform_policy.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';

void main() {
  test('清理范围发现不占用 UI Isolate', () async {
    final List<CleanupScanTarget> targets =
        await CleanupBackgroundRunner.discoverTargets();
    expect(
      targets.every((CleanupScanTarget target) => target.id.isNotEmpty),
      isTrue,
    );
  });

  test('后台发现可合并外部规则且不会修改固定长度内置列表', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vibekits_external_cleanup_rule_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final String database = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'catalogVersion': 99,
      'rules': <Object?>[
        <String, Object?>{
          'id': 'external-test-cache',
          'label': '外部测试缓存',
          'platform': 'windows',
          'pathTemplate': r'%TEST_CACHE%',
          'category': 'applicationCache',
          'risk': 'safe',
          'defaultEnabled': true,
          'cleanupAction': 'recycle',
          'impact': '测试目录可重新生成',
        },
      ],
    }).replaceAll(r'%TEST_CACHE%', directory.path.replaceAll(r'\', r'\\'));

    final List<CleanupScanTarget> targets =
        await CleanupBackgroundRunner.discoverTargets(
          bundledRuleDatabase: database,
          platform: CleanupPlatform.windows,
        );

    expect(
      targets.map((CleanupScanTarget target) => target.id),
      contains('external-test-cache'),
    );
  });

  test('后台扫描可跨 Isolate 接收进度并取消', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vibekits_background_scan_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    for (int index = 0; index < 800; index++) {
      File(
        '${directory.path}${Platform.pathSeparator}$index.tmp',
      ).writeAsStringSync('cache-$index');
    }
    final CleanupCancellationToken token = CleanupCancellationToken();
    int progressEvents = 0;

    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      <CleanupScanTarget>[
        CleanupScanTarget(
          id: 'test-background',
          label: '后台测试',
          path: directory.path,
          category: CleanupCategory.userTemp,
          defaultEnabled: true,
        ),
      ],
      cancellationToken: token,
      onProgress: (CleanupScanProgress progress) {
        progressEvents++;
        token.cancel();
      },
    );

    expect(result.cancelled, isTrue);
    expect(progressEvents, greaterThan(0));
    expect(result.candidates.length, lessThan(800));
  });

  test('两个有界工作线程合并候选和进度', () async {
    expect(CleanupBackgroundRunner.maxScanWorkers, 2);
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_parallel_scan_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory first = Directory(
      '${sandbox.path}${Platform.pathSeparator}first',
    )..createSync();
    final Directory second = Directory(
      '${sandbox.path}${Platform.pathSeparator}second',
    )..createSync();
    for (int index = 0; index < 40; index++) {
      File(
        '${first.path}${Platform.pathSeparator}$index.log',
      ).writeAsStringSync('first-$index');
      File(
        '${second.path}${Platform.pathSeparator}$index.log',
      ).writeAsStringSync('second-$index');
    }
    final List<int> visitedProgress = <int>[];
    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      <CleanupScanTarget>[
        CleanupScanTarget(
          id: 'parallel-first',
          label: '并行一',
          path: first.path,
          category: CleanupCategory.logs,
          defaultEnabled: true,
        ),
        CleanupScanTarget(
          id: 'parallel-second',
          label: '并行二',
          path: second.path,
          category: CleanupCategory.logs,
          defaultEnabled: true,
        ),
      ],
      cancellationToken: CleanupCancellationToken(),
      onProgress: (CleanupScanProgress progress) {
        visitedProgress.add(progress.visitedEntries);
      },
    );

    expect(result.cancelled, isFalse);
    expect(result.candidates, hasLength(80));
    expect(result.visitedEntries, 80);
    expect(visitedProgress, isNotEmpty);
    expect(visitedProgress.last, 80);
  });
}
