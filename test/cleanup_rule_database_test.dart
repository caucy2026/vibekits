import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_rule_database.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  test('版本化规则只接收有界回收站规则并保留风险与影响', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_rule_database_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File oldCache = File('${root.path}${Platform.pathSeparator}old.cache')
      ..writeAsStringSync('cache');
    oldCache.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 3)),
    );
    final String source = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'catalogVersion': 5,
      'rules': <Object?>[
        <String, Object?>{
          'id': 'test-safe-cache',
          'label': '测试缓存',
          'platform': 'windows',
          'pathTemplate': r'%LOCALAPPDATA%',
          'category': 'applicationCache',
          'risk': 'safe',
          'defaultEnabled': true,
          'minimumAgeHours': 24,
          'maxDepth': 2,
          'maxEntries': 20,
          'cleanupAction': 'recycle',
          'impact': '可重新生成',
        },
        <String, Object?>{
          'id': 'test-dangerous-command',
          'label': '危险规则',
          'platform': 'windows',
          'pathTemplate': r'%LOCALAPPDATA%',
          'category': 'logs',
          'risk': 'safe',
          'cleanupAction': 'command',
          'impact': '不得执行',
        },
      ],
    });

    final CleanupRuleDatabaseResult database = CleanupRuleDatabase.parse(
      source,
      environment: <String, String>{'LOCALAPPDATA': root.path},
      platform: 'windows',
      windowsBuild: 22631,
    );

    expect(database.catalogVersion, 5);
    expect(database.targets, hasLength(1));
    expect(database.rejectedRules, hasLength(1));
    expect(database.targets.single.riskLevel, CleanupRiskLevel.safe);
    expect(database.targets.single.safetyNote, '可重新生成');
    expect(database.targets.single.maxEntries, 20);

    final result = await CleanupScanner.scanTargets(database.targets);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.path, oldCache.path);
    expect(result.candidates.single.impactNote, '可重新生成');
    expect(result.candidates.single.defaultSelected, isTrue);
  });

  test('未知 schema 会整体拒绝且不会猜测执行', () {
    expect(
      () => CleanupRuleDatabase.parse(
        '{"schemaVersion":2,"catalogVersion":1,"rules":[]}',
        platform: 'windows',
      ),
      throwsFormatException,
    );
  });
}
