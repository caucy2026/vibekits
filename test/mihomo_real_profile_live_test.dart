import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mihomo_controller_service.dart';
import 'package:vibekits/features/dev_tools/domain/mihomo_profile_service.dart';
import 'package:vibekits/features/dev_tools/domain/network_virtualization_service.dart';

void main() {
  const String release = String.fromEnvironment('VIBEKITS_LIVE_RELEASE');
  const String profilePath = String.fromEnvironment('VIBEKITS_LIVE_PROFILE');
  final bool enabled =
      Platform.isWindows && release.isNotEmpty && profilePath.isNotEmpty;

  test('真实 Clash Profile 使用内置 GeoData 启动并暴露节点', () async {
    final File source = File(profilePath);
    expect(source.existsSync(), isTrue);
    final Directory data = Directory(
      '${Directory.current.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}acceptance${Platform.pathSeparator}real-profile',
    );
    await data.create(recursive: true);
    final String yaml = await source.readAsString();
    final MihomoProfile profile = MihomoProfile(
      id: 'live-profile',
      name: '真实订阅验收',
      path: source.path,
      sourceHost: '已脱敏',
      updatedAt: DateTime.now(),
      summary: MihomoConfigSummary.parse(yaml),
      subscription: false,
    );
    final MihomoProfileService profiles = MihomoProfileService(
      dataDirectory: data.path,
      credentialReader: (_) async => null,
      credentialWriter: (_, _) async {},
      credentialDeleter: (_) async {},
      proxyResolver: () async => null,
    );
    final MihomoManagedConfig config = await profiles.prepareManagedConfig(
      profile,
    );
    Future<void> noLifecycle(int _) async {}
    try {
      await NetworkVirtualizationService.startMihomo(
        configPath: config.path,
        dataDirectory: data.path,
        executable:
            '$release${Platform.pathSeparator}tools${Platform.pathSeparator}'
            'mihomo${Platform.pathSeparator}mihomo.exe',
        bindProcessTree: noLifecycle,
        releaseProcessTree: noLifecycle,
      );
      final MihomoControllerService controller = MihomoControllerService(
        config.summary.controller!,
        secret: config.summary.secret,
      );
      MihomoControllerSnapshot? snapshot;
      for (int attempt = 0; attempt < 30 && snapshot == null; attempt++) {
        try {
          snapshot = await controller.snapshot();
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(snapshot, isNotNull);
      expect(config.summary.proxyCount, 32);
      expect(snapshot!.groups, isNotEmpty);
      expect(
        snapshot.groups
            .expand((MihomoProxyGroup group) => group.nodes)
            .toSet()
            .length,
        greaterThanOrEqualTo(32),
      );
      final List<String> candidates = snapshot.groups
          .expand((MihomoProxyGroup group) => group.nodes)
          .where(
            (String node) => !const <String>{
              'DIRECT',
              'REJECT',
              'REJECT-DROP',
              'PASS',
              'COMPATIBLE',
            }.contains(node.toUpperCase()),
          )
          .toSet()
          .take(6)
          .toList();
      final List<int?> delays = await Future.wait<int?>(
        candidates.map((String node) async {
          try {
            return await controller.testDelay(node);
          } on Object {
            return null;
          }
        }),
      );
      expect(delays.whereType<int>(), isNotEmpty);
    } finally {
      await NetworkVirtualizationService.stopMihomo();
    }
  }, skip: enabled ? false : '设置 Release 和脱敏 Profile 路径后运行');
}
