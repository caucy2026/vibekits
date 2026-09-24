import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/app_update_service.dart';
import 'runtime_component_verifier.dart';
import '../../dev_tools/domain/network_virtualization_service.dart';

typedef AppCenterCatalogLoader =
    Future<AppCenterCatalog> Function({String? category, String keyword});
typedef AppCenterEnvelopeLoader = Future<Object?> Function(Uri uri);
typedef AppCenterInstalledLookup = Future<bool> Function(String packageName);
typedef AppCenterVersionLookup =
    Future<AppCenterLocalVersion> Function(String packageName);
typedef AppCenterApplicationOpener = Future<bool> Function(String packageName);

@immutable
class AppCenterLocalVersion {
  const AppCenterLocalVersion.uninstalled()
    : installed = false,
      versionCode = null;
  const AppCenterLocalVersion.installed(this.versionCode) : installed = true;
  const AppCenterLocalVersion.unknown() : installed = null, versionCode = null;

  final bool? installed;
  final int? versionCode;
}

enum AppCenterUpdateStatus {
  checking,
  install,
  update,
  current,
  downgrade,
  unknown,
}

@immutable
class AppCenterCategory {
  const AppCenterCategory({required this.name, this.isExplore = false});

  final String name;
  final bool isExplore;
}

@immutable
class AppCenterItem {
  const AppCenterItem({
    required this.appId,
    required this.name,
    required this.packageName,
    required this.androidPackageName,
    required this.versionName,
    required this.versionCode,
    required this.category,
    required this.shortDescription,
    required this.longDescription,
    required this.iconUrl,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSizeBytes,
    required this.rating,
    required this.downloadCount,
    required this.osType,
    required this.platforms,
    this.artifactType = 'app',
    this.hostPackageName = '',
    this.componentId = '',
    this.standalone = true,
  });

  static const componentPackages = <String, String>{
    'com.caucy.vibekits.component.virtual_machine': 'virtual_machine',
    'com.caucy.vibekits.component.network_proxy': 'network_proxy',
    'com.vibekits.vibekits.component.models': 'android_models',
  };

  factory AppCenterItem.fromJson(Map<String, Object?> json) {
    // The current market contract stores package identity, but does not yet
    // expose component metadata. Only these two exact reserved IDs opt in.
    final component = componentPackages['${json['package_name'] ?? ''}'.trim()];
    return AppCenterItem(
      appId: _asInt(json['app_id']),
      name: '${json['app_name'] ?? ''}'.trim(),
      packageName: '${json['package_name'] ?? ''}'.trim(),
      androidPackageName:
          '${json['android_package_name'] ?? json['application_id'] ?? ''}'
              .trim(),
      versionName: '${json['version_name'] ?? ''}'.trim(),
      versionCode: _asInt(json['version_code']),
      category: '${json['category'] ?? ''}'.trim(),
      shortDescription: '${json['short_desc'] ?? ''}'.trim(),
      longDescription: '${json['long_desc'] ?? ''}'.trim(),
      iconUrl: '${json['icon'] ?? ''}'.trim(),
      downloadUrl: '${json['download_url'] ?? ''}'.trim(),
      sha256: '${json['apk_sha256'] ?? json['sha256'] ?? ''}'
          .trim()
          .toLowerCase(),
      fileSizeBytes: _asInt(json['file_size_bytes'] ?? json['file_size']),
      rating: _asDouble(json['rating'], fallback: 5),
      downloadCount: _asInt(json['download_count']),
      osType: '${json['os_type'] ?? ''}'.trim().toLowerCase(),
      platforms: (json['platforms'] is List<Object?>
          ? (json['platforms']! as List<Object?>)
                .map((entry) => '$entry'.trim().toLowerCase())
                .where((entry) => entry.isNotEmpty)
                .toList(growable: false)
          : const <String>[]),
      artifactType: component != null
          ? 'component'
          : '${json['artifact_type'] ?? 'app'}'.trim().toLowerCase(),
      hostPackageName:
          '${json['host_package_name'] ?? (component == 'android_models'
                      ? 'com.vibekits.vibekits'
                      : component == 'network_proxy' && '${json['os_type'] ?? ''}'.trim().toLowerCase() == 'android'
                      ? 'com.vibekits.vibekits'
                      : component != null
                      ? AppUpdateService.packageName
                      : '')}'
              .trim(),
      componentId: '${json['component_id'] ?? component ?? ''}'
          .trim()
          .toLowerCase(),
      standalone: json['standalone'] != null
          ? json['standalone'] != false
          : component == null,
    );
  }

  final int appId;
  final String name;
  final String packageName;

  /// Android 原生 applicationId。`packageName` 是跨平台商品标识，二者不能混用。
  final String androidPackageName;
  String get androidInstallPackageName => androidPackageName.isNotEmpty
      ? androidPackageName
      : packageName == AppUpdateService.packageName
      ? 'com.vibekits.vibekits'
      : packageName;
  final String versionName;
  final int versionCode;
  final String category;
  final String shortDescription;
  final String longDescription;
  final String iconUrl;
  final String downloadUrl;
  final String sha256;
  final int fileSizeBytes;
  final double rating;
  final int downloadCount;
  final String osType;
  final List<String> platforms;
  final String artifactType;
  final String hostPackageName;
  final String componentId;
  final bool standalone;

  bool get isComponent => artifactType == 'component';

  bool supportsPlatform(String platform) {
    final String normalized = platform.trim().toLowerCase();
    if (osType.isNotEmpty && osType != normalized) return false;
    final Set<String> compatible = switch (normalized) {
      // The KEMI Android storefront currently returns PAD packages as `pad2`
      // even when the request is scoped with `os=android`. `all` is the
      // documented cross-device value used by newly published applications.
      'android' => const <String>{'android', 'pad2', 'all'},
      'macos' => const <String>{'macos', 'all'},
      'windows' => const <String>{'windows', 'all'},
      _ => <String>{normalized},
    };
    if (platforms.isNotEmpty && !platforms.any(compatible.contains)) {
      return false;
    }
    return osType == normalized || platforms.any(compatible.contains);
  }

  bool get hasVerifiedInstaller {
    final Uri? uri = Uri.tryParse(downloadUrl);
    if (uri == null || uri.scheme != 'https' || fileSizeBytes <= 0) {
      return false;
    }
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256);
  }

  static int _asInt(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : int.tryParse('$value') ?? 0;

  static double _asDouble(Object? value, {double fallback = 0}) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
}

@immutable
class AppCenterCatalog {
  const AppCenterCatalog({
    required this.categories,
    required this.apps,
    required this.total,
  });

  final List<AppCenterCategory> categories;
  final List<AppCenterItem> apps;
  final int total;
}

class AppCenterService {
  AppCenterService({
    HttpClient? client,
    String apiRoot = _defaultApiRoot,
    String? platformOverride,
    AppCenterCatalogLoader? loader,
    AppCenterEnvelopeLoader? envelopeLoader,
    AppCenterInstalledLookup? installedLookup,
    AppCenterVersionLookup? versionLookup,
    AppCenterApplicationOpener? applicationOpener,
  }) : _client = client ?? HttpClient(),
       _apiRoot = apiRoot,
       _platformOverride = platformOverride,
       _loader = loader,
       _envelopeLoader = envelopeLoader,
       _installedLookup = installedLookup,
       _versionLookup = versionLookup,
       _applicationOpener = applicationOpener;

  static const String _defaultApiRoot = 'https://kemi.newlinksz.com/kd-api';
  static const MethodChannel _desktopHostChannel = MethodChannel(
    'org.rustdesk.rustdesk/host',
  );
  static const Duration _desktopHostTimeout = Duration(seconds: 3);
  static const int _catalogPageSize = 30;
  static const int _maxCatalogPages = 200;

  final HttpClient _client;
  final String _apiRoot;
  final String? _platformOverride;
  final AppCenterCatalogLoader? _loader;
  final AppCenterEnvelopeLoader? _envelopeLoader;
  final AppCenterInstalledLookup? _installedLookup;
  final AppCenterVersionLookup? _versionLookup;
  final AppCenterApplicationOpener? _applicationOpener;

  Future<AppCenterLocalVersion> localVersion(AppCenterItem item) async {
    if (item.isComponent && platformName == 'android') {
      if (!((item.componentId == 'android_models' &&
                  item.packageName ==
                      'com.vibekits.vibekits.component.models') ||
              (item.componentId == 'network_proxy' &&
                  item.packageName ==
                      'com.caucy.vibekits.component.network_proxy')) ||
          item.hostPackageName != 'com.vibekits.vibekits' ||
          !item.supportsPlatform('android')) {
        return const AppCenterLocalVersion.unknown();
      }
    } else if (item.isComponent) {
      if (!const {
            'virtual_machine',
            'network_proxy',
          }.contains(item.componentId) ||
          item.hostPackageName != AppUpdateService.packageName) {
        return const AppCenterLocalVersion.unknown();
      }
      final File receipt;
      try {
        receipt = File(
          '${RuntimeComponentVerifier.activeDirectory(item.componentId).path}/component.json',
        );
      } on Object {
        return const AppCenterLocalVersion.unknown();
      }
      if (!await receipt.exists()) {
        return const AppCenterLocalVersion.uninstalled();
      }
      try {
        final Map<String, dynamic> data =
            jsonDecode(await receipt.readAsString()) as Map<String, dynamic>;
        final code = data['version_code'];
        if (data['host_package_name'] != item.hostPackageName ||
            data['component_id'] != item.componentId ||
            code is! int ||
            code <= 0) {
          return const AppCenterLocalVersion.unknown();
        }
        return AppCenterLocalVersion.installed(code);
      } on Object {
        return const AppCenterLocalVersion.unknown();
      }
    }
    final String? os = platformName;
    if (os == null || !item.supportsPlatform(os)) {
      return const AppCenterLocalVersion.unknown();
    }
    final String packageName = os == 'android'
        ? item.androidInstallPackageName
        : item.packageName;
    if (!_isSafePackageName(packageName)) {
      return const AppCenterLocalVersion.unknown();
    }
    try {
      if (_versionLookup != null) {
        return await _versionLookup(packageName).timeout(_desktopHostTimeout);
      }
      final String channel = os == 'android'
          ? 'vibekits/app-installer'
          : 'org.rustdesk.rustdesk/host';
      final Map<Object?, Object?>? value = await MethodChannel(channel)
          .invokeMapMethod<Object?, Object?>(
            'getStoreApplicationVersion',
            <String, Object?>{'packageName': packageName},
          )
          .timeout(_desktopHostTimeout);
      if (value == null || value['installed'] is! bool) {
        return const AppCenterLocalVersion.unknown();
      }
      if (value['installed'] == false) {
        return const AppCenterLocalVersion.uninstalled();
      }
      final Object? rawCode = value['versionCode'];
      final int? code = rawCode is int ? rawCode : int.tryParse('$rawCode');
      return AppCenterLocalVersion.installed(code);
    } on Object {
      return const AppCenterLocalVersion.unknown();
    }
  }

  AppCenterUpdateStatus updateStatus(
    AppCenterItem item,
    AppCenterLocalVersion local,
  ) {
    if (item.versionCode <= 0 || local.installed == null) {
      return AppCenterUpdateStatus.unknown;
    }
    if (local.installed == false) return AppCenterUpdateStatus.install;
    final int? code = local.versionCode;
    if (code == null || code <= 0) return AppCenterUpdateStatus.unknown;
    if (item.versionCode > code) return AppCenterUpdateStatus.update;
    return item.versionCode == code
        ? AppCenterUpdateStatus.current
        : AppCenterUpdateStatus.downgrade;
  }

  bool canDownload(AppCenterItem item, AppCenterLocalVersion local) {
    final String? os = platformName;
    if (os == null ||
        !item.supportsPlatform(os) ||
        !item.hasVerifiedInstaller) {
      return false;
    }
    try {
      _allowedExtension(Uri.parse(item.downloadUrl).path, os);
    } on FormatException {
      return false;
    }
    final AppCenterUpdateStatus status = updateStatus(item, local);
    return status == AppCenterUpdateStatus.install ||
        status == AppCenterUpdateStatus.update;
  }

  bool get supportsOpeningInstalledApplications =>
      platformName == 'windows' || platformName == 'macos';

  Future<bool> isApplicationInstalled(AppCenterItem item) async {
    if (item.isComponent ||
        !supportsOpeningInstalledApplications ||
        !_isSafePackageName(item.packageName)) {
      return false;
    }
    try {
      final Future<bool> lookup =
          _installedLookup?.call(item.packageName) ??
          _desktopHostChannel
              .invokeMethod<bool>(
                'isStoreApplicationInstalled',
                <String, Object?>{'packageName': item.packageName},
              )
              .then((bool? installed) => installed == true);
      return await lookup.timeout(_desktopHostTimeout, onTimeout: () => false);
    } on Object {
      return false;
    }
  }

  Future<bool> openApplication(AppCenterItem item) async {
    if (item.isComponent ||
        !supportsOpeningInstalledApplications ||
        !_isSafePackageName(item.packageName)) {
      return false;
    }
    try {
      final Future<bool> opener =
          _applicationOpener?.call(item.packageName) ??
          _desktopHostChannel
              .invokeMethod<bool>('openStoreApplication', <String, Object?>{
                'packageName': item.packageName,
              })
              .then((bool? opened) => opened == true);
      return await opener.timeout(_desktopHostTimeout, onTimeout: () => false);
    } on Object {
      return false;
    }
  }

  static bool _isSafePackageName(String value) =>
      value.isNotEmpty && RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

  String? get platformName {
    if (_platformOverride != null) return _platformOverride;
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  Future<AppCenterCatalog> load({String? category, String keyword = ''}) async {
    if (_loader != null) {
      return _loader(category: category, keyword: keyword);
    }
    final String? os = platformName;
    if (os == null) throw UnsupportedError('应用中心仅支持 Windows、macOS 和 Android');
    final List<Object?> rawCategories = await _getList(
      Uri.parse('$_apiRoot/api/store/categories'),
    );
    final List<AppCenterCategory> categories = rawCategories
        .whereType<Map<String, Object?>>()
        .where((entry) => entry['enabled'] != false && entry['enabled'] != 0)
        .map(
          (entry) => AppCenterCategory(
            name: '${entry['name'] ?? ''}'.trim(),
            isExplore: entry['is_explore'] == true || entry['is_explore'] == 1,
          ),
        )
        .where((entry) => entry.name.isNotEmpty)
        .toList(growable: false);
    final Map<String, String> query = <String, String>{
      'pageSize': '$_catalogPageSize',
      'os': os,
    };
    if (category != null && category.trim().isNotEmpty) {
      query['category'] = category.trim();
    }
    if (keyword.trim().isNotEmpty) query['keyword'] = keyword.trim();
    final Map<String, AppCenterItem> appsByIdentity = <String, AppCenterItem>{};
    int total = 0;
    bool catalogComplete = false;
    for (int page = 1; page <= _maxCatalogPages; page++) {
      final Map<String, Object?> data = await _getData(
        Uri.parse(
          '$_apiRoot/api/store/apps',
        ).replace(queryParameters: <String, String>{...query, 'page': '$page'}),
      );
      final List<Object?> rawApps = data['list'] is List<Object?>
          ? data['list']! as List<Object?>
          : const <Object?>[];
      final int reportedTotal = AppCenterItem._asInt(data['total']);
      if (reportedTotal > total) total = reportedTotal;
      for (final AppCenterItem item
          in rawApps
              .whereType<Map<String, Object?>>()
              .map(AppCenterItem.fromJson)
              .where((item) => item.supportsPlatform(os))) {
        final String identity = item.appId > 0
            ? '${item.appId}'
            : '${item.packageName}\u0000${item.osType}\u0000${item.versionCode}';
        appsByIdentity[identity] = item;
      }
      if (rawApps.isEmpty ||
          rawApps.length < _catalogPageSize ||
          (total > 0 && page * _catalogPageSize >= total)) {
        catalogComplete = true;
        break;
      }
    }
    if (!catalogComplete) {
      throw const FormatException('应用市场分页超过安全上限');
    }
    final List<AppCenterItem> apps = appsByIdentity.values.toList(
      growable: false,
    );
    return AppCenterCatalog(
      categories: categories,
      apps: apps,
      total: total > apps.length ? total : apps.length,
    );
  }

  Future<String> downloadAndOpen(
    AppCenterItem item, {
    ValueChanged<double>? onProgress,
  }) async {
    if (item.isComponent && platformName != 'android') {
      throw StateError('VibeKits 组件必须由宿主程序安装，不能作为独立应用打开');
    }
    final String? os = platformName;
    final AppCenterLocalVersion local = await localVersion(item);
    if (!canDownload(item, local)) throw StateError('本机版本未确认或市场版本未高于已安装版本');
    if (!const {'windows', 'macos', 'android'}.contains(os) ||
        !item.supportsPlatform(os!) ||
        !item.hasVerifiedInstaller) {
      throw const FormatException('安装包缺少当前系统、HTTPS、大小或 SHA-256 验证信息');
    }
    final Uri uri = Uri.parse(item.downloadUrl);
    final String extension = _allowedExtension(uri.path, os);
    final Directory temporary = await getTemporaryDirectory();
    final File output = File(
      '${temporary.path}${Platform.pathSeparator}KEMI-${item.packageName}-${item.versionCode}$extension',
    );
    try {
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('下载返回 HTTP ${response.statusCode}');
      }
      final IOSink sink = output.openWrite();
      int received = 0;
      try {
        await for (final List<int> chunk in response) {
          received += chunk.length;
          if (received > item.fileSizeBytes) {
            throw const FormatException('下载大小超过市场声明');
          }
          sink.add(chunk);
          onProgress?.call(received / item.fileSizeBytes);
        }
      } finally {
        await sink.close();
      }
      if (received != item.fileSizeBytes) {
        throw const FormatException('下载字节数与市场声明不一致');
      }
      final String actual = (await sha256.bind(output.openRead()).first)
          .toString()
          .toLowerCase();
      if (actual != item.sha256) {
        throw const FormatException('安装包 SHA-256 校验失败');
      }
      await _openInstaller(output.path, extension, os, item);
      return output.path;
    } on Object {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  /// Downloads and installs a VibeKits runtime component. Components are
  /// extracted into a versioned user directory and activated by an atomic
  /// versioned directory and active-pointer switch; they are never opened as applications.
  Future<String> installComponent(
    AppCenterItem item, {
    ValueChanged<double>? onProgress,
  }) async {
    if (platformName == 'android') {
      if (!item.isComponent ||
          !((item.componentId == 'android_models' &&
                  item.packageName ==
                      'com.vibekits.vibekits.component.models') ||
              (item.componentId == 'network_proxy' &&
                  item.packageName ==
                      'com.caucy.vibekits.component.network_proxy')) ||
          item.hostPackageName != 'com.vibekits.vibekits' ||
          item.standalone ||
          !item.supportsPlatform('android')) {
        throw const FormatException('不是 VibeKits Android 模型组件');
      }
      return downloadAndOpen(item, onProgress: onProgress);
    }
    if (!item.isComponent ||
        item.standalone ||
        !const {
          'virtual_machine',
          'network_proxy',
        }.contains(item.componentId) ||
        item.hostPackageName != AppUpdateService.packageName) {
      throw const FormatException('市场条目不是 VibeKits 宿主组件');
    }
    final String? os = platformName;
    if (!const {'windows', 'macos'}.contains(os) ||
        !item.supportsPlatform(os!) ||
        !item.hasVerifiedInstaller ||
        !(Uri.parse(item.downloadUrl).path.toLowerCase().endsWith('.zip') ||
            (os == 'windows' &&
                Uri.parse(
                  item.downloadUrl,
                ).path.toLowerCase().endsWith('.exe')))) {
      throw const FormatException('组件缺少当前平台、HTTPS、大小或 SHA-256 信息');
    }
    final local = await localVersion(item);
    if (!canDownload(item, local)) {
      throw StateError('组件版本未确认或市场版本未高于已安装版本');
    }
    final bool executableInstaller = Uri.parse(
      item.downloadUrl,
    ).path.toLowerCase().endsWith('.exe');
    final Directory temporary = await getTemporaryDirectory();
    final File archiveFile = File(
      '${temporary.path}${Platform.pathSeparator}KEMI-component-'
      '${item.componentId}-${item.versionCode}${executableInstaller ? '.exe' : '.zip'}',
    );
    try {
      final HttpClientRequest request = await _client
          .getUrl(Uri.parse(item.downloadUrl))
          .timeout(const Duration(seconds: 15));
      // The market returns the final CDN URL. Reject redirects instead of
      // allowing an HTTPS request to downgrade to an unverified destination.
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw FormatException('组件下载返回 HTTP ${response.statusCode}');
      }
      final IOSink sink = archiveFile.openWrite();
      int received = 0;
      try {
        await for (final List<int> chunk in response) {
          received += chunk.length;
          if (received > item.fileSizeBytes) {
            throw const FormatException('组件大小超过市场声明');
          }
          sink.add(chunk);
          onProgress?.call(received / item.fileSizeBytes);
        }
      } finally {
        await sink.close();
      }
      if (received != item.fileSizeBytes) {
        throw const FormatException('组件大小与市场声明不一致');
      }
      final String actual = (await sha256.bind(archiveFile.openRead()).first)
          .toString()
          .toLowerCase();
      if (actual != item.sha256) {
        throw const FormatException('组件 SHA-256 校验失败');
      }
      if (executableInstaller) {
        await RuntimeComponentVerifier.verifyWindowsInstaller(archiveFile.path);
        final process = await Process.start(archiveFile.path, [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/SP-',
        ], runInShell: false);
        await Future.wait<void>([
          process.stdout.drain<void>(),
          process.stderr.drain<void>(),
        ]);
        final exitCode = await process.exitCode;
        if (exitCode != 0) throw StateError('组件安装失败：$exitCode，原版本保持不变');
        final root = RuntimeComponentVerifier.activeDirectory(item.componentId);
        await RuntimeComponentVerifier.verify(
          root,
          item.componentId,
          versionCode: item.versionCode,
        );
        return root.path;
      }
      return await _extractComponent(item, archiveFile);
    } finally {
      if (await archiveFile.exists()) await archiveFile.delete();
    }
  }

  Future<void> uninstallComponent(AppCenterItem item) async {
    if (!item.isComponent ||
        item.standalone ||
        item.hostPackageName != AppUpdateService.packageName) {
      throw const FormatException('不是当前主程序的组件');
    }
    final root = RuntimeComponentVerifier.componentDirectory(item.componentId);
    final status = NetworkVirtualizationService.status();
    final running = item.componentId == 'virtual_machine'
        ? status['qemuRunning']
        : status['mihomoRunning'];
    if (running == true) throw StateError('请先停止正在运行的组件');
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('组件目录异常，已停止卸载');
    }
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<String> _extractComponent(AppCenterItem item, File archiveFile) async {
    final String separator = Platform.pathSeparator;
    final Directory component = RuntimeComponentVerifier.componentDirectory(
      item.componentId,
    );
    await component.create(recursive: true);
    final Directory stage = await component.createTemp(
      '.staging-${item.versionCode}-',
    );
    final Directory version = Directory(
      '${component.path}$separator${item.versionCode}',
    );
    bool promoted = false;
    bool activated = false;
    try {
      final Archive decoded = ZipDecoder().decodeBytes(
        await archiveFile.readAsBytes(),
        verify: true,
      );
      for (final ArchiveFile entry in decoded) {
        final String normalized = entry.name.replaceAll('\\', '/');
        if (normalized.startsWith('/') ||
            normalized.contains(':') ||
            normalized.split('/').contains('..') ||
            entry.isSymbolicLink) {
          throw const FormatException('组件压缩包包含非法路径');
        }
        final List<String> parts = normalized
            .split('/')
            .where((String part) => part.isNotEmpty)
            .toList(growable: false);
        if (parts.isEmpty) continue;
        final File target = File(
          '${stage.path}$separator${parts.join(separator)}',
        );
        if (entry.isFile) {
          await target.parent.create(recursive: true);
          await target.writeAsBytes(entry.content, flush: true);
        } else {
          await Directory(target.path).create(recursive: true);
        }
      }
      final String runtimeDirectory = item.componentId == 'virtual_machine'
          ? 'qemu'
          : 'mihomo';
      final Directory expected = Directory(
        '${stage.path}${separator}tools$separator$runtimeDirectory',
      );
      final Directory direct = Directory(
        '${stage.path}$separator$runtimeDirectory',
      );
      if (!expected.existsSync() && !direct.existsSync()) {
        throw const FormatException('组件压缩包缺少运行时目录');
      }
      if (!direct.existsSync()) await expected.rename(direct.path);
      final List<String> executables = runtimeDirectory == 'qemu'
          ? <String>['qemu-system-x86_64', 'qemu-img']
          : <String>['mihomo'];
      for (final String name in executables) {
        final File executable = File(
          '${direct.path}/$name${Platform.isWindows ? '.exe' : ''}',
        );
        if (!await executable.exists()) {
          throw const FormatException('组件压缩包缺少运行程序');
        }
        if (Platform.isMacOS) {
          final ProcessResult result = await Process.run('/bin/chmod', <String>[
            'u+x',
            executable.path,
          ]);
          if (result.exitCode != 0) {
            throw const FormatException('无法设置组件运行权限');
          }
        }
      }
      await RuntimeComponentVerifier.verify(
        stage,
        item.componentId,
        versionCode: item.versionCode,
      );
      await RuntimeComponentVerifier.probe(stage, item.componentId);
      await File('${stage.path}/component.json').writeAsString(
        jsonEncode({
          'component_id': item.componentId,
          'host_package_name': item.hostPackageName,
          'version_code': item.versionCode,
          'sha256': item.sha256,
        }),
      );
      await component.create(recursive: true);
      if (await version.exists()) {
        throw const FormatException('同版本组件目录已经存在，请检查安装状态');
      }
      await stage.rename(version.path);
      promoted = true;
      final File active = File('${component.path}/active.json');
      final File pending = File('${component.path}/active.pending.json');
      final File backup = File('${component.path}/active.previous.json');
      await pending.writeAsString(
        jsonEncode({'version_code': item.versionCode}),
        flush: true,
      );
      if (await backup.exists()) await backup.delete();
      if (await active.exists()) await active.rename(backup.path);
      try {
        await pending.rename(active.path);
      } catch (_) {
        if (await backup.exists()) await backup.rename(active.path);
        rethrow;
      }
      activated = true;
      return version.path;
    } catch (_) {
      if (promoted && !activated && await version.exists()) {
        await version.delete(recursive: true);
      }
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }

  Future<Map<String, Object?>> _getData(Uri uri) async {
    final Object? data = await _getEnvelopeData(uri);
    if (data is! Map<String, Object?>) {
      throw const FormatException('应用市场缺少对象 data');
    }
    return data;
  }

  Future<Object?> _getEnvelopeData(Uri uri) async {
    if (_envelopeLoader != null) return _envelopeLoader(uri);
    final HttpClientRequest request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 12),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw FormatException('应用市场返回 HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['status'] != 200) {
      throw const FormatException('应用市场响应格式不兼容');
    }
    return decoded['data'];
  }

  Future<List<Object?>> _getList(Uri uri) async {
    final Object? data = await _getEnvelopeData(uri);
    if (data is List<Object?>) return data;
    if (data is! Map<String, Object?>) {
      throw const FormatException('应用市场分类格式不兼容');
    }
    final Object? list = data['list'] ?? data['categories'];
    if (list is List<Object?>) return list;
    throw const FormatException('应用市场分类格式不兼容');
  }

  static String _allowedExtension(String path, String os) {
    final String lower = path.toLowerCase();
    final List<String> allowed = switch (os) {
      'macos' => const <String>['.dmg', '.pkg', '.zip'],
      'android' => const <String>['.apk'],
      _ => const <String>['.exe', '.msi', '.zip'],
    };
    return allowed.firstWhere(
      lower.endsWith,
      orElse: () => throw const FormatException('安装包格式不受支持'),
    );
  }

  static Future<void> _openInstaller(
    String path,
    String extension,
    String os,
    AppCenterItem item,
  ) async {
    if (os == 'android') {
      await const MethodChannel(
        'vibekits/app-installer',
      ).invokeMethod<void>('openApkInstaller', <String, Object?>{
        'path': path,
        'packageName': item.androidInstallPackageName,
        'versionCode': item.versionCode,
        'hostComponent': item.isComponent,
      });
    } else if (os == 'macos') {
      await Process.start('open', <String>[
        path,
      ], mode: ProcessStartMode.detached);
    } else if (extension == '.msi') {
      await Process.start('msiexec', <String>[
        '/i',
        path,
      ], mode: ProcessStartMode.detached);
    } else if (extension == '.exe') {
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start('explorer.exe', <String>[
        path,
      ], mode: ProcessStartMode.detached);
    }
  }

  void dispose() => _client.close(force: true);
}
