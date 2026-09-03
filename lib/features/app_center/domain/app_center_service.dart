import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef AppCenterCatalogLoader =
    Future<AppCenterCatalog> Function({String? category, String keyword});
typedef AppCenterEnvelopeLoader = Future<Object?> Function(Uri uri);

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
  });

  factory AppCenterItem.fromJson(Map<String, Object?> json) => AppCenterItem(
    appId: _asInt(json['app_id']),
    name: '${json['app_name'] ?? ''}'.trim(),
    packageName: '${json['package_name'] ?? ''}'.trim(),
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
  );

  final int appId;
  final String name;
  final String packageName;
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

  bool supportsPlatform(String platform) =>
      osType == platform || (osType.isEmpty && platforms.contains(platform));

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
  }) : _client = client ?? HttpClient(),
       _apiRoot = apiRoot,
       _platformOverride = platformOverride,
       _loader = loader,
       _envelopeLoader = envelopeLoader;

  static const String _defaultApiRoot = 'https://kemi.newlinksz.com/kd-api';

  final HttpClient _client;
  final String _apiRoot;
  final String? _platformOverride;
  final AppCenterCatalogLoader? _loader;
  final AppCenterEnvelopeLoader? _envelopeLoader;

  String? get platformName {
    if (_platformOverride != null) return _platformOverride;
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return null;
  }

  Future<AppCenterCatalog> load({String? category, String keyword = ''}) async {
    if (_loader != null) {
      return _loader(category: category, keyword: keyword);
    }
    final String? os = platformName;
    if (os == null) throw UnsupportedError('应用中心仅支持 Windows 和 macOS');
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
      'page': '1',
      'pageSize': '100',
      'os': os,
    };
    if (category != null && category.trim().isNotEmpty) {
      query['category'] = category.trim();
    }
    if (keyword.trim().isNotEmpty) query['keyword'] = keyword.trim();
    final Map<String, Object?> data = await _getData(
      Uri.parse('$_apiRoot/api/store/apps').replace(queryParameters: query),
    );
    final List<Object?> rawApps = data['list'] is List<Object?>
        ? data['list']! as List<Object?>
        : const <Object?>[];
    final List<AppCenterItem> apps = rawApps
        .whereType<Map<String, Object?>>()
        .map(AppCenterItem.fromJson)
        .where((item) => item.supportsPlatform(os))
        .toList(growable: false);
    return AppCenterCatalog(
      categories: categories,
      apps: apps,
      total: AppCenterItem._asInt(data['total']),
    );
  }

  Future<String> downloadAndOpen(
    AppCenterItem item, {
    ValueChanged<double>? onProgress,
  }) async {
    final String? os = platformName;
    if (os == null ||
        !item.supportsPlatform(os) ||
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
      await _openInstaller(output.path, extension, os);
      return output.path;
    } on Object {
      if (await output.exists()) await output.delete();
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
    final List<String> allowed = os == 'macos'
        ? const <String>['.dmg', '.pkg', '.zip']
        : const <String>['.exe', '.msi', '.zip'];
    return allowed.firstWhere(
      lower.endsWith,
      orElse: () => throw const FormatException('安装包格式不受支持'),
    );
  }

  static Future<void> _openInstaller(
    String path,
    String extension,
    String os,
  ) async {
    if (os == 'macos') {
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
