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

  void dispose() {
    if (_ownsMarket) _market.dispose();
  }
}
