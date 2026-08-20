import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/cleaner/domain/installed_application_service.dart';
import 'package:vibekits/features/cleaner/domain/software_storage_analyzer.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analyzer.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_insights.dart';

void main() {
  test('Windows 真实注册表能发现带名称的软件清单', () async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<InstalledApplication> apps =
        await InstalledApplicationService.load();
    stopwatch.stop();
    debugPrint(
      'CLEANER_PERF|installed_apps=${apps.length}|'
      'registry_ms=${stopwatch.elapsedMilliseconds}',
    );
    expect(apps, isNotEmpty);
    expect(
      apps.every((InstalledApplication app) => app.name.isNotEmpty),
      isTrue,
    );
  }, skip: !Platform.isWindows);

  test('解析 Windows 卸载注册表并过滤系统组件', () {
    const String output = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Acme
    DisplayName    REG_SZ    Acme IDE
    Publisher    REG_SZ    Acme Inc.
    DisplayVersion    REG_SZ    3.2.1
    InstallLocation    REG_SZ    C:\Program Files\Acme
    EstimatedSize    REG_DWORD    2048
    UninstallString    REG_SZ    "C:\Program Files\Acme\uninstall.exe" /remove

HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Hidden
    DisplayName    REG_SZ    Internal Runtime
    SystemComponent    REG_DWORD    0x1
''';

    final List<InstalledApplication> apps =
        InstalledApplicationService.parseRegistryQuery(output);
    expect(apps, hasLength(1));
    expect(apps.single.name, 'Acme IDE');
    expect(apps.single.publisher, 'Acme Inc.');
    expect(apps.single.estimatedSizeBytes, 2048 * 1024);
    expect(apps.single.canUninstall, isTrue);
  });

  test('同一软件聚合安装、数据和可清缓存并判断异常', () {
    const int gib = 1024 * 1024 * 1024;
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\',
      entries: <SystemDriveUsageEntry>[],
      breakdownEntries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Program Files\Acme',
          name: 'Acme',
          sizeBytes: 10 * gib,
          kind: SystemDriveEntryKind.installedPrograms,
          reason: '安装目录',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Program Files',
        ),
        SystemDriveUsageEntry(
          path: r'C:\Users\me\AppData\Local\Acme',
          name: 'me / AppData / Local / Acme',
          sizeBytes: 12 * gib,
          kind: SystemDriveEntryKind.softwareData,
          reason: '软件数据',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Users',
        ),
        SystemDriveUsageEntry(
          path: r'C:\Users\me\AppData\Local\Acme\Cache',
          name: 'me / AppData / Local / Acme / Cache',
          sizeBytes: 6 * gib,
          kind: SystemDriveEntryKind.logsAndCaches,
          reason: '缓存',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Users',
          deletePolicy: SystemDriveDeletePolicy.recycleAfterConfirmation,
        ),
      ],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: 100,
      measuredBytes: 22 * gib,
      totalBytes: 100 * gib,
      freeBytes: 10 * gib,
      availableBytes: 10 * gib,
    );
    const InstalledApplication app = InstalledApplication(
      id: 'acme',
      name: 'Acme IDE',
      installLocation: r'C:\Program Files\Acme',
      uninstallCommand: r'"C:\Program Files\Acme\uninstall.exe"',
    );

    final SoftwareStorageSummary summary = SoftwareStorageAnalyzer.summarize(
      analysis,
      const <InstalledApplication>[app],
    ).single;
    expect(summary.name, 'Acme IDE');
    expect(summary.installBytes, 10 * gib);
    expect(summary.dataBytes, 12 * gib);
    expect(summary.cacheBytes, 6 * gib);
    expect(summary.totalBytes, 22 * gib);
    expect(summary.level, SystemDriveAssessmentLevel.critical);
    expect(summary.canCleanCache, isTrue);
    expect(summary.canUninstall, isTrue);
    expect(summary.installPaths, <String>[r'C:\Program Files\Acme']);
  });

  test('注册表没有安装路径时使用扫描到的真实安装目录', () {
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\',
      entries: <SystemDriveUsageEntry>[],
      breakdownEntries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Program Files\Acme',
          name: 'Acme',
          sizeBytes: 1024,
          kind: SystemDriveEntryKind.installedPrograms,
          reason: '安装目录',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Program Files',
        ),
      ],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: 1,
      measuredBytes: 1024,
      totalBytes: 4096,
      freeBytes: 2048,
      availableBytes: 2048,
    );
    const InstalledApplication app = InstalledApplication(
      id: 'acme',
      name: 'Acme',
    );
    final SoftwareStorageSummary summary = SoftwareStorageAnalyzer.summarize(
      analysis,
      const <InstalledApplication>[app],
    ).single;
    expect(summary.installPaths, <String>[r'C:\Program Files\Acme']);
  });

  test('系统盘扫描单独产出软件缓存目录而不是只能看到 AppData 总量', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_software_cache_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory cache = Directory(
      '${root.path}${Platform.pathSeparator}Users'
      '${Platform.pathSeparator}tester${Platform.pathSeparator}AppData'
      '${Platform.pathSeparator}Local${Platform.pathSeparator}Code'
      '${Platform.pathSeparator}Cache',
    )..createSync(recursive: true);
    File('${cache.path}${Platform.pathSeparator}blob.bin')
        .writeAsBytesSync(List<int>.filled(4096, 1));

    final SystemDriveAnalysis analysis = await SystemDriveAnalyzer.analyze(
      root.path,
    );
    final SystemDriveUsageEntry cacheEntry = analysis.breakdownEntries
        .firstWhere(
          (SystemDriveUsageEntry entry) =>
              entry.kind == SystemDriveEntryKind.logsAndCaches,
        );
    expect(cacheEntry.path, cache.path);
    expect(cacheEntry.ownerLabel, 'Code');
    expect(cacheEntry.sizeBytes, 4096);
    expect(cacheEntry.canDelete, isTrue);
  });

  test('未匹配到真实安装项的聚合目录只分析不允许一键清理', () {
    const SoftwareStorageSummary aggregate = SoftwareStorageSummary(
      id: 'microsoft',
      name: 'Microsoft',
      installBytes: 0,
      dataBytes: 1024,
      cacheBytes: 1024,
      level: SystemDriveAssessmentLevel.normal,
      assessment: '聚合目录',
      installEntries: <SystemDriveUsageEntry>[],
      dataEntries: <SystemDriveUsageEntry>[],
      cacheEntries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Users\me\AppData\Local\Microsoft\Cache',
          name: 'Cache',
          sizeBytes: 1024,
          kind: SystemDriveEntryKind.logsAndCaches,
          reason: '缓存',
          isDirectory: true,
          complete: true,
          deletePolicy: SystemDriveDeletePolicy.recycleAfterConfirmation,
        ),
      ],
    );
    expect(aggregate.canCleanCache, isFalse);
  });
}
