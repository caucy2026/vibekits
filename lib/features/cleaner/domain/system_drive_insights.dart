import 'system_drive_analyzer.dart';

enum SystemDriveAssessmentLevel {
  normal('正常'),
  attention('偏大'),
  review('需复核'),
  critical('优先处理');

  const SystemDriveAssessmentLevel(this.label);

  final String label;
}

class SystemDriveEntryAssessment {
  const SystemDriveEntryAssessment({
    required this.entry,
    required this.level,
    required this.summary,
    required this.basis,
    required this.suggestedAction,
  });

  final SystemDriveUsageEntry entry;
  final SystemDriveAssessmentLevel level;
  final String summary;
  final String basis;
  final String suggestedAction;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': entry.path,
    'name': entry.name,
    'owner': entry.ownerLabel,
    'sizeBytes': entry.sizeBytes,
    'kind': entry.kind.name,
    'kindLabel': entry.kind.label,
    'level': level.name,
    'levelLabel': level.label,
    'summary': summary,
    'basis': basis,
    'suggestedAction': suggestedAction,
    'canDeleteAfterConfirmation': entry.canDelete,
    'measurementComplete': entry.complete,
  };
}

/// Turns raw directory sizes into bounded, explainable recommendations.
///
/// These are deliberately heuristics rather than deletion rules. Hardware,
/// installed roles and Windows update state vary, so an assessment may suggest
/// review but can never make a protected entry deletable.
class SystemDriveInsights {
  const SystemDriveInsights({
    required this.storagePressure,
    required this.storagePressureSummary,
    required this.systemBaseline,
    required this.categoryTotals,
    required this.assessments,
  });

  static const int _gib = 1024 * 1024 * 1024;

  final SystemDriveAssessmentLevel storagePressure;
  final String storagePressureSummary;
  final String systemBaseline;
  final Map<SystemDriveEntryKind, int> categoryTotals;
  final List<SystemDriveEntryAssessment> assessments;

  List<SystemDriveEntryAssessment> get priorities => assessments
      .where(
        (SystemDriveEntryAssessment item) =>
            item.level != SystemDriveAssessmentLevel.normal,
      )
      .toList(growable: false);

  List<SystemDriveEntryAssessment> get softwareOwners => assessments
      .where(
        (SystemDriveEntryAssessment item) =>
            item.entry.isBreakdown &&
            <SystemDriveEntryKind>{
              SystemDriveEntryKind.installedPrograms,
              SystemDriveEntryKind.softwareData,
              SystemDriveEntryKind.logsAndCaches,
            }.contains(item.entry.kind),
      )
      .toList(growable: false);

  factory SystemDriveInsights.from(SystemDriveAnalysis analysis) {
    final Map<SystemDriveEntryKind, int> categoryTotals =
        <SystemDriveEntryKind, int>{};
    for (final SystemDriveUsageEntry entry in analysis.entries) {
      categoryTotals.update(
        entry.kind,
        (int value) => value + entry.sizeBytes,
        ifAbsent: () => entry.sizeBytes,
      );
    }
    final List<SystemDriveUsageEntry> entries = <SystemDriveUsageEntry>[
      ...analysis.entries,
      ...analysis.breakdownEntries,
    ];
    final List<SystemDriveEntryAssessment> assessments =
        entries
            .map(
              (SystemDriveUsageEntry entry) =>
                  _assessEntry(entry, totalBytes: analysis.totalBytes),
            )
            .toList(growable: false)
          ..sort((
            SystemDriveEntryAssessment left,
            SystemDriveEntryAssessment right,
          ) {
            final int severity = right.level.index.compareTo(left.level.index);
            if (severity != 0) return severity;
            return right.entry.sizeBytes.compareTo(left.entry.sizeBytes);
          });
    final double freeRatio = analysis.totalBytes <= 0
        ? 1
        : analysis.freeBytes / analysis.totalBytes;
    final SystemDriveAssessmentLevel pressure = freeRatio < 0.05
        ? SystemDriveAssessmentLevel.critical
        : freeRatio < 0.10
        ? SystemDriveAssessmentLevel.review
        : freeRatio < 0.20
        ? SystemDriveAssessmentLevel.attention
        : SystemDriveAssessmentLevel.normal;
    return SystemDriveInsights(
      storagePressure: pressure,
      storagePressureSummary: switch (pressure) {
        SystemDriveAssessmentLevel.critical =>
          '系统盘剩余不足 5%，更新、编译和虚拟内存都可能失败，应优先处理可确认的缓存、日志和不用的软件。',
        SystemDriveAssessmentLevel.review => '系统盘剩余不足 10%，建议复核大体积软件数据、构建缓存和日志。',
        SystemDriveAssessmentLevel.attention =>
          '系统盘剩余不足 20%，当前可用，但应关注持续增长的软件缓存和日志。',
        SystemDriveAssessmentLevel.normal => '系统盘剩余空间处于正常范围。',
      },
      systemBaseline: 'Windows 10/11 的系统目录逻辑量常见约 20–40 GiB；更新、驱动、语言包、休眠和 NTFS 硬链接会改变数字。超过范围只表示需要用系统维护工具复核，不表示可以直接删除。',
      categoryTotals: Map<SystemDriveEntryKind, int>.unmodifiable(
        categoryTotals,
      ),
      assessments: List<SystemDriveEntryAssessment>.unmodifiable(assessments),
    );
  }

  static SystemDriveEntryAssessment _assessEntry(
    SystemDriveUsageEntry entry, {
    required int totalBytes,
  }) {
    final int bytes = entry.sizeBytes;
    final double share = totalBytes <= 0 ? 0 : bytes / totalBytes;
    return switch (entry.kind) {
      SystemDriveEntryKind.windowsSystem =>
        bytes > 60 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.review,
                'Windows 系统逻辑量明显偏大',
                '超过 60 GiB；组件存储硬链接可能重复计数。',
                '先查看 Windows 更新、可选组件和 DISM 组件存储分析，禁止手工删除系统目录。',
              )
            : bytes > 40 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                'Windows 系统逻辑量高于常见区间',
                '常见启发式区间约 20–40 GiB，具体取决于版本、驱动和更新。',
                '使用 Windows 官方存储/组件维护入口复核，不直接删除。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.normal,
                'Windows 系统占用处于常见逻辑量区间',
                '未超过 40 GiB 启发式上界；这不是最低安装需求。',
                '保持不动；需要腾空间时使用 Windows 官方维护入口。',
              ),
      SystemDriveEntryKind.logsAndCaches =>
        bytes >= 5 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.critical,
                '日志或缓存异常大',
                '单项达到 5 GiB，通常值得优先确认来源与保留期。',
                '关闭对应软件，核对文件年龄和规则后从清理候选页处理。',
              )
            : bytes >= _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.review,
                '日志或缓存较大',
                '单项达到 1 GiB，可能持续增长或可重新生成。',
                '先确认软件仍是否使用，再按明确规则清理，不整目录盲删。',
              )
            : bytes >= 256 * 1024 * 1024
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                '日志或缓存值得关注',
                '单项达到 256 MiB。',
                '观察增长速度；空间紧张时进入清理候选复核。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.review,
                '日志或缓存体积较小，删除前仍需复核',
                '未达到 256 MiB 关注阈值。',
                '通常无需处理。',
              ),
      SystemDriveEntryKind.unknown =>
        bytes >= 5 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.critical,
                '未知来源占用很大',
                '系统盘未知单项达到 5 GiB。',
                '让智能体结合目录名、签名、进程和修改时间判断来源；确认前不要删除。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.review,
                '未知来源需要识别',
                bytes >= _gib ? '未知单项达到 1 GiB。' : '根目录项目不在已知系统清单中。',
                '先识别所属软件和是否仍在使用，确认后才允许进入回收站。',
              ),
      SystemDriveEntryKind.softwareData =>
        bytes >= 10 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.review,
                '软件数据很大',
                '单个软件数据来源达到 10 GiB。',
                '检查缓存、下载、索引、容器镜像和历史版本；保留配置与数据库。',
              )
            : bytes >= 3 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                '软件数据偏大',
                '单个软件数据来源达到 3 GiB。',
                '按软件用途展开，区分可再生缓存与用户数据。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.normal,
                '软件数据未达到关注阈值',
                '单项低于 3 GiB。',
                '无需仅因体积删除。',
              ),
      SystemDriveEntryKind.installedPrograms =>
        share >= 0.30
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                '安装程序占系统盘比例较高',
                '该项达到磁盘总容量的 30%；安装软件没有统一合理大小。',
                '按软件/SDK 展开并卸载不用版本，不直接删安装目录。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.normal,
                '已安装程序需要按用途判断',
                '安装软件不存在统一大小基线。',
                '只通过卸载器移除不用的软件或 SDK。',
              ),
      SystemDriveEntryKind.userData =>
        share >= 0.45
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                '用户数据占系统盘比例较高',
                '该项达到磁盘总容量的 45%。',
                '继续展开下载、媒体、项目和 AppData；不要把源码和文档当垃圾。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.normal,
                '用户数据大小取决于实际内容',
                '用户文件不存在统一合理大小。',
                '按内容和用途管理，不按目录整体清理。',
              ),
      SystemDriveEntryKind.recovery || SystemDriveEntryKind.systemManaged =>
        bytes >= 15 * _gib
            ? _assessment(
                entry,
                SystemDriveAssessmentLevel.attention,
                '系统管理空间较大',
                '单项达到 15 GiB。',
                '使用系统设置检查还原点、休眠或恢复策略，不手工删除。',
              )
            : _assessment(
                entry,
                SystemDriveAssessmentLevel.normal,
                '由 Windows 管理',
                '容量取决于休眠、恢复点和系统策略。',
                '保持不动；需要调整时使用系统设置。',
              ),
    };
  }

  static SystemDriveEntryAssessment _assessment(
    SystemDriveUsageEntry entry,
    SystemDriveAssessmentLevel level,
    String summary,
    String basis,
    String action,
  ) => SystemDriveEntryAssessment(
    entry: entry,
    level: level,
    summary: summary,
    basis: basis,
    suggestedAction: action,
  );
}
