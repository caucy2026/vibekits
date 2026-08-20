import 'dart:convert';
import 'dart:io';

import 'cleanup_scanner.dart';
import 'cleanup_targets.dart';

class CleanupRuleDatabaseResult {
  const CleanupRuleDatabaseResult({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.targets,
    required this.rejectedRules,
  });

  final int schemaVersion;
  final int catalogVersion;
  final List<CleanupScanTarget> targets;
  final List<String> rejectedRules;
}

/// Parses the bundled, versioned cleaner database into executable scan targets.
///
/// The database is data-only: it cannot execute arbitrary commands. Every rule
/// is bounded by age, depth, entry count and an explicit risk level. Unsupported
/// or malformed rules are rejected individually without blocking built-in rules.
abstract final class CleanupRuleDatabase {
  static const int supportedSchemaVersion = 1;

  static CleanupRuleDatabaseResult parse(
    String source, {
    Map<String, String>? environment,
    String? platform,
    int windowsBuild = 99999,
  }) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('清理规则数据库根节点必须是对象');
    }
    final int schemaVersion = _integer(decoded['schemaVersion']);
    final int catalogVersion = _integer(decoded['catalogVersion']);
    if (schemaVersion != supportedSchemaVersion || catalogVersion <= 0) {
      throw FormatException(
        '不支持的清理规则数据库版本：schema=$schemaVersion catalog=$catalogVersion',
      );
    }
    final Object? rawRules = decoded['rules'];
    if (rawRules is! List<Object?>) {
      throw const FormatException('清理规则数据库缺少 rules 数组');
    }
    final Map<String, String> env = environment ?? Platform.environment;
    final String currentPlatform = (platform ?? Platform.operatingSystem)
        .toLowerCase();
    final Set<String> ids = <String>{};
    final List<CleanupScanTarget> targets = <CleanupScanTarget>[];
    final List<String> rejected = <String>[];
    for (int index = 0; index < rawRules.length; index++) {
      final Object? raw = rawRules[index];
      if (raw is! Map<String, Object?>) {
        rejected.add('#$index：规则不是对象');
        continue;
      }
      final String id = '${raw['id'] ?? ''}'.trim();
      try {
        if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$').hasMatch(id)) {
          throw const FormatException('id 无效');
        }
        if (!ids.add(id)) throw const FormatException('id 重复');
        final String rulePlatform = '${raw['platform'] ?? ''}'.toLowerCase();
        if (rulePlatform != currentPlatform) continue;
        final int minimumBuild = _optionalInteger(raw['minimumBuild'], 0);
        final int maximumBuild = _optionalInteger(raw['maximumBuild'], 999999);
        if (currentPlatform == 'windows' &&
            (windowsBuild < minimumBuild || windowsBuild > maximumBuild)) {
          continue;
        }
        final String? path = _expandPath('${raw['pathTemplate'] ?? ''}', env);
        // A rule describes supported software, not only what exists during
        // this launch. Keeping absent targets makes the configured scope
        // stable across restarts; the scanner cheaply skips missing paths.
        if (path == null) continue;
        final CleanupRiskLevel risk = _risk('${raw['risk'] ?? ''}');
        final String action = '${raw['cleanupAction'] ?? ''}';
        if (action != 'recycle') {
          throw const FormatException('只允许 recycle 清理动作');
        }
        final int maxDepth = _optionalInteger(raw['maxDepth'], 8);
        final int maxEntries = _optionalInteger(raw['maxEntries'], 5000);
        final int minimumAgeHours = _optionalInteger(
          raw['minimumAgeHours'],
          24,
        );
        if (maxDepth < 0 ||
            maxDepth > 16 ||
            maxEntries <= 0 ||
            maxEntries > 100000 ||
            minimumAgeHours < 0) {
          throw const FormatException('扫描边界无效');
        }
        targets.add(
          CleanupScanTarget(
            id: id,
            label: _requiredText(raw, 'label'),
            path: path,
            category: _category('${raw['category'] ?? ''}'),
            defaultEnabled: raw['defaultEnabled'] == true,
            safetyNote: _requiredText(raw, 'impact'),
            minimumAgeHours: minimumAgeHours,
            maxDepth: maxDepth,
            maxEntries: maxEntries,
            minimumSizeBytes: _optionalInteger(raw['minimumSizeBytes'], 0),
            includePatterns: _strings(raw['includePatterns']),
            excludePatterns: _strings(raw['excludePatterns']),
            ruleCatalogVersion: catalogVersion,
            riskLevel: risk,
            ruleSource: '${raw['source'] ?? 'Vibekits 规则数据库'}',
          ),
        );
      } on FormatException catch (error) {
        rejected.add('${id.isEmpty ? '#$index' : id}：${error.message}');
      }
    }
    return CleanupRuleDatabaseResult(
      schemaVersion: schemaVersion,
      catalogVersion: catalogVersion,
      targets: List<CleanupScanTarget>.unmodifiable(targets),
      rejectedRules: List<String>.unmodifiable(rejected),
    );
  }

  static int _integer(Object? value) {
    if (value is int) return value;
    throw const FormatException('版本号必须是整数');
  }

  static int _optionalInteger(Object? value, int fallback) =>
      value == null ? fallback : _integer(value);

  static String _requiredText(Map<String, Object?> rule, String key) {
    final String value = '${rule[key] ?? ''}'.trim();
    if (value.isEmpty) throw FormatException('$key 不能为空');
    return value;
  }

  static CleanupRiskLevel _risk(String value) => switch (value) {
    'safe' => CleanupRiskLevel.safe,
    'cautious' => CleanupRiskLevel.cautious,
    'systemManaged' => CleanupRiskLevel.systemManaged,
    _ => throw const FormatException('risk 无效'),
  };

  static CleanupCategory _category(String value) => switch (value) {
    'browserCache' => CleanupCategory.browserCache,
    'applicationCache' => CleanupCategory.applicationCache,
    'systemCache' => CleanupCategory.systemCache,
    'developerCache' => CleanupCategory.devCache,
    'pluginCache' => CleanupCategory.pluginCache,
    'debugArtifacts' => CleanupCategory.debugArtifacts,
    'logs' => CleanupCategory.logs,
    _ => throw const FormatException('category 无效'),
  };

  static List<String> _strings(Object? value) {
    if (value == null) return const <String>[];
    if (value is! List<Object?> ||
        value.any((Object? item) => item is! String)) {
      throw const FormatException('文件模式必须是字符串数组');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  static String? _expandPath(String template, Map<String, String> environment) {
    if (template.trim().isEmpty) return null;
    final Map<String, String> normalized = <String, String>{
      for (final MapEntry<String, String> item in environment.entries)
        item.key.toUpperCase(): item.value,
    };
    bool missing = false;
    final String expanded = template.replaceAllMapped(RegExp(r'%([^%]+)%'), (
      Match match,
    ) {
      final String? value = normalized[match.group(1)!.toUpperCase()];
      if (value == null || value.trim().isEmpty) {
        missing = true;
        return '';
      }
      return value.trim();
    });
    if (missing) return null;
    return expanded
        .replaceAll('\\', Platform.pathSeparator)
        .replaceAll('/', Platform.pathSeparator);
  }
}
