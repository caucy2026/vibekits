import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_center/domain/app_center_service.dart';

enum PadBuilderComponentState {
  installed,
  availableInMarket,
  notListed,
  incompleteMarketRecord,
  unknownLocalState,
}

@immutable
class PadBuilderComponentStatus {
  const PadBuilderComponentStatus(this.state, {this.versionCode, this.item});

  final PadBuilderComponentState state;
  final int? versionCode;
  final AppCenterItem? item;

  String get nextAction => switch (state) {
    PadBuilderComponentState.installed => '检查组件自检结果，确认 buildReady=true 后再编译',
    PadBuilderComponentState.availableInMarket =>
      '调用 vibekits.android.builder_component_install 从 KEMI 商城安装，等待系统安装确认后重新检查',
    PadBuilderComponentState.notListed =>
      'KEMI 商城尚未上架 PAD 编译组件；保留当前任务和源码，报告无法在 PAD 本机编译',
    PadBuilderComponentState.incompleteMarketRecord =>
      '商城记录缺少可信的 HTTPS、精确大小、SHA-256、包名或版本；停止安装并报告缺失项',
    PadBuilderComponentState.unknownLocalState =>
      '本机安装状态尚未确认；重试组件状态检查，不能改用 Termux 或其他下载源',
  };
}

/// Only reports installation and market availability. A separate build-service
/// handshake must prove the toolchain works before Harness advertises builds.
class PadBuilderComponentService {
  PadBuilderComponentService({AppCenterService? market})
    : _market = market ?? AppCenterService(),
      _ownsMarket = market == null;

  static const String packageName = 'com.vibekits.vibekits.component.builder';

  final AppCenterService _market;
  final bool _ownsMarket;

  Future<PadBuilderComponentStatus> check() async {
    if (_market.platformName != 'android') {
      throw UnsupportedError('PAD 编译组件仅适用于 Android');
    }
    final probe = AppCenterItem.fromJson(const <String, Object?>{
      'package_name': packageName,
      'os_type': 'android',
    });
    final local = await _market.localVersion(probe);
    if (local.installed == true &&
        local.versionCode != null &&
        local.versionCode! > 0) {
      return PadBuilderComponentStatus(
        PadBuilderComponentState.installed,
        versionCode: local.versionCode,
      );
    }
    if (local.installed != false) {
      return const PadBuilderComponentStatus(
        PadBuilderComponentState.unknownLocalState,
      );
    }
    final AppCenterCatalog catalog = await _market.load();
    final matching = catalog.apps.where(
      (item) => item.packageName == packageName,
    );
    if (matching.isEmpty) {
      return const PadBuilderComponentStatus(
        PadBuilderComponentState.notListed,
      );
    }
    final item = matching.first;
    if (!item.isTrustedAndroidHostComponent ||
        !item.hasVerifiedInstaller ||
        item.versionCode <= 0 ||
        !Uri.parse(item.downloadUrl).path.toLowerCase().endsWith('.apk')) {
      return const PadBuilderComponentStatus(
        PadBuilderComponentState.incompleteMarketRecord,
      );
    }
    return PadBuilderComponentStatus(
      PadBuilderComponentState.availableInMarket,
      item: item,
    );
  }

  Future<String> requestInstall(
    PadBuilderComponentStatus status, {
    ValueChanged<double>? onProgress,
  }) {
    if (status.item == null ||
        status.state != PadBuilderComponentState.availableInMarket) {
      throw StateError('编译组件未上架或市场安装信息不完整');
    }
    return _market.installComponent(status.item!, onProgress: onProgress);
  }

  /// Waits only for the exact package to appear in PackageManager. This does
  /// not access the catalog again or treat an opened installer as success.
  Future<PadBuilderComponentStatus?> waitForInstall({
    Duration timeout = const Duration(seconds: 90),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (_market.platformName != 'android') {
      throw UnsupportedError('PAD 编译组件仅适用于 Android');
    }
    if (timeout < Duration.zero || pollInterval <= Duration.zero) {
      throw ArgumentError('安装等待时间无效');
    }
    final probe = AppCenterItem.fromJson(const <String, Object?>{
      'package_name': packageName,
      'os_type': 'android',
    });
    final watch = Stopwatch()..start();
    while (true) {
      final local = await _market.localVersion(probe);
      if (local.installed == true &&
          local.versionCode != null &&
          local.versionCode! > 0) {
        return PadBuilderComponentStatus(
          PadBuilderComponentState.installed,
          versionCode: local.versionCode,
        );
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) return null;
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
  }

  void dispose() {
    if (_ownsMarket) _market.dispose();
  }
}
