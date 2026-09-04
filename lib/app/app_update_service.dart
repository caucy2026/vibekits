import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';

enum AppUpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  failed,
}

@immutable
class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    this.phase = AppUpdatePhase.idle,
    this.versionName = '',
    this.versionCode = 0,
    this.releaseNotes = '',
    this.progress = 0,
    this.forceUpdate = false,
    this.message = '',
    this.packagePath,
  });

  final AppUpdatePhase phase;
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final double progress;
  final bool forceUpdate;
  final String message;
  final String? packagePath;
}

class AppUpdateService {
  AppUpdateService({
    HttpClient? client,
    String apiRoot = _defaultApiRoot,
    String? platformOverride,
  }) : _client = client ?? HttpClient(),
       _apiRoot = apiRoot,
       _platformOverride = platformOverride;

  static final AppUpdateService instance = AppUpdateService();
  static const String packageName = 'com.caucy.vibekits';
  static const String _defaultApiRoot = 'https://kemi.newlinksz.com/kd-api';

  final HttpClient _client;
  final String _apiRoot;
  final String? _platformOverride;
  final ValueNotifier<AppUpdateSnapshot> snapshot =
      ValueNotifier<AppUpdateSnapshot>(const AppUpdateSnapshot());
  _RemoteUpdate? _remote;
  bool _started = false;

  static String? get platformName {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return null;
  }

  Future<void> start() async {
    if (_started || (_platformOverride ?? platformName) == null) return;
    _started = true;
    await check();
  }

  void dispose() {
    _client.close(force: true);
    snapshot.dispose();
  }

  Future<void> check() async {
    final String? os = _platformOverride ?? platformName;
    if (os == null) return;
    snapshot.value = const AppUpdateSnapshot(
      phase: AppUpdatePhase.checking,
      message: '正在检查更新…',
    );
    try {
      final Uri uri = Uri.parse('$_apiRoot/api/store/update/check').replace(
        queryParameters: <String, String>{
          'package_name': packageName,
          'version_code': '${AppVersion.build}',
          'os': os,
        },
      );
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('更新服务返回 HTTP ${response.statusCode}');
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['status'] != 200) {
        throw const FormatException('更新服务响应格式不兼容');
      }
      final Object? rawData = decoded['data'];
      if (rawData is! Map<String, Object?>) {
        throw const FormatException('更新服务缺少 data');
      }
      if (rawData['has_update'] != true) {
        _remote = null;
        snapshot.value = const AppUpdateSnapshot(
          phase: AppUpdatePhase.current,
          message: '当前已是最新版本',
        );
        return;
      }
      final _RemoteUpdate remote = _RemoteUpdate.fromJson(rawData, os: os);
      if (remote.versionCode <= AppVersion.build) {
        throw const FormatException('更新版本号没有高于当前版本');
      }
      _remote = remote;
      snapshot.value = AppUpdateSnapshot(
        phase: AppUpdatePhase.available,
        versionName: remote.versionName,
        versionCode: remote.versionCode,
        releaseNotes: remote.releaseNotes,
        forceUpdate: remote.forceUpdate,
        message: '发现新版本 ${remote.versionName}',
      );
    } on Object catch (error) {
      debugPrint('App update check failed: $error');
      snapshot.value = AppUpdateSnapshot(
        phase: AppUpdatePhase.failed,
        message: '暂时无法检查更新，请稍后重试',
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final _RemoteUpdate? remote = _remote;
    if (remote == null) return;
    File? output;
    try {
      snapshot.value = AppUpdateSnapshot(
        phase: AppUpdatePhase.downloading,
        versionName: remote.versionName,
        versionCode: remote.versionCode,
        releaseNotes: remote.releaseNotes,
        forceUpdate: remote.forceUpdate,
        message: '正在下载安装包…',
      );
      final Directory temp = await getTemporaryDirectory();
      final String extension = remote.extension;
      output = File(
        '${temp.path}${Platform.pathSeparator}Vibekits-update-${remote.versionCode}$extension',
      );
      final HttpClientRequest request = await _client.getUrl(
        remote.downloadUrl,
      );
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('下载返回 HTTP ${response.statusCode}');
      }
      final IOSink sink = output.openWrite();
      int received = 0;
      await for (final List<int> chunk in response) {
        received += chunk.length;
        if (received > remote.fileSize) {
          throw const FormatException('下载大小超过服务端声明');
        }
        sink.add(chunk);
        snapshot.value = AppUpdateSnapshot(
          phase: AppUpdatePhase.downloading,
          versionName: remote.versionName,
          versionCode: remote.versionCode,
          releaseNotes: remote.releaseNotes,
          forceUpdate: remote.forceUpdate,
          progress: received / remote.fileSize,
          message:
              '正在下载 ${(received / remote.fileSize * 100).clamp(0, 100).toStringAsFixed(0)}%',
        );
      }
      await sink.close();
      if (received != remote.fileSize) throw const FormatException('安装包字节数不一致');
      final String actual = (await sha256.bind(output.openRead()).first)
          .toString()
          .toLowerCase();
      if (actual != remote.sha256) {
        throw const FormatException('安装包 SHA-256 校验失败');
      }
      snapshot.value = AppUpdateSnapshot(
        phase: AppUpdatePhase.ready,
        versionName: remote.versionName,
        versionCode: remote.versionCode,
        releaseNotes: remote.releaseNotes,
        forceUpdate: remote.forceUpdate,
        progress: 1,
        packagePath: output.path,
        message: '校验通过，正在打开系统安装器…',
      );
      await _openInstaller(output.path, extension);
    } on Object catch (error) {
      if (output != null && await output.exists()) await output.delete();
      snapshot.value = AppUpdateSnapshot(
        phase: AppUpdatePhase.failed,
        versionName: remote.versionName,
        versionCode: remote.versionCode,
        releaseNotes: remote.releaseNotes,
        forceUpdate: remote.forceUpdate,
        message: '更新失败：$error',
      );
    }
  }

  Future<void> _openInstaller(String path, String extension) async {
    if (Platform.isMacOS) {
      await Process.start('open', <String>[
        path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isWindows && extension == '.msi') {
      await Process.start('msiexec', <String>[
        '/i',
        path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isWindows && extension == '.exe') {
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    if (Platform.isWindows && extension == '.zip') {
      await Process.start('explorer.exe', <String>[
        path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    throw UnsupportedError('不支持的安装包格式');
  }
}

class _RemoteUpdate {
  const _RemoteUpdate({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSize,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.extension,
  });

  factory _RemoteUpdate.fromJson(
    Map<String, Object?> json, {
    required String os,
  }) {
    final int versionCode = _int(json['version_code']);
    final Uri? downloadUrl = Uri.tryParse(
      '${json['download_url'] ?? json['apk_url'] ?? ''}',
    );
    final String checksum = '${json['sha256'] ?? json['apk_sha256'] ?? ''}'
        .toLowerCase();
    final int fileSize = _int(json['file_size_bytes'] ?? json['file_size']);
    if (json['os_type'] != os ||
        downloadUrl == null ||
        downloadUrl.scheme != 'https') {
      throw const FormatException('更新来源系统或 HTTPS 地址无效');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) || fileSize <= 0) {
      throw const FormatException('更新包大小或 SHA-256 无效');
    }
    final String extension = _allowedExtension(downloadUrl.path, os);
    return _RemoteUpdate(
      versionName: '${json['version_name'] ?? versionCode}',
      versionCode: versionCode,
      downloadUrl: downloadUrl,
      sha256: checksum,
      fileSize: fileSize,
      forceUpdate: json['force_update'] == true,
      releaseNotes: '${json['release_notes'] ?? json['short_desc'] ?? ''}',
      extension: extension,
    );
  }

  final String versionName;
  final int versionCode;
  final Uri downloadUrl;
  final String sha256;
  final int fileSize;
  final bool forceUpdate;
  final String releaseNotes;
  final String extension;

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? -1;

  static String _allowedExtension(String path, String os) {
    final String lower = path.toLowerCase();
    final List<String> allowed = os == 'macos'
        ? const <String>['.dmg', '.pkg', '.zip']
        : const <String>['.exe', '.msi', '.zip'];
    return allowed.firstWhere(
      lower.endsWith,
      orElse: () => throw const FormatException('安装包扩展名不受支持'),
    );
  }
}
