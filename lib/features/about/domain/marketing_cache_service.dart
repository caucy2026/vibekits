import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_codec;

import '../../../app/atomic_file.dart';
import '../../../app/platform_storage_layout.dart';

enum MarketingCacheState { loading, syncing, ready, offline }

class MarketingCachedImage {
  const MarketingCachedImage({
    required this.name,
    required this.path,
    required this.sortOrder,
  });

  final String name;
  final String path;
  final int sortOrder;
}

class MarketingCacheSnapshot {
  const MarketingCacheSnapshot({
    required this.state,
    this.version = '',
    this.images = const <MarketingCachedImage>[],
    this.failureCategory = '',
  });

  const MarketingCacheSnapshot.loading()
    : state = MarketingCacheState.loading,
      version = '',
      images = const <MarketingCachedImage>[],
      failureCategory = '';

  final MarketingCacheState state;
  final String version;
  final List<MarketingCachedImage> images;
  final String failureCategory;

  bool get hasImages => images.isNotEmpty;
}

class MarketingRemoteFile {
  const MarketingRemoteFile({
    required this.name,
    required this.url,
    required this.mime,
    required this.md5Digest,
    required this.size,
    required this.sortOrder,
  });

  final String name;
  final Uri url;
  final String mime;
  final String md5Digest;
  final int size;
  final int sortOrder;
}

class MarketingRemoteManifest {
  const MarketingRemoteManifest({
    required this.name,
    required this.version,
    required this.files,
  });

  final String name;
  final String version;
  final List<MarketingRemoteFile> files;
}

typedef MarketingManifestLoader = Future<MarketingRemoteManifest> Function();
typedef MarketingBytesLoader =
    Future<Uint8List> Function(MarketingRemoteFile file);

class MarketingCacheService {
  MarketingCacheService({
    required this.cacheRoot,
    MarketingManifestLoader? manifestLoader,
    MarketingBytesLoader? bytesLoader,
  }) : _manifestLoader = manifestLoader ?? _loadProductionManifest,
       _bytesLoader = bytesLoader ?? _loadProductionBytes;

  static const String resourceName = 'kemi_s1_xc';
  static final Uri endpoint = Uri.https(
    'kemi.newlinksz.com',
    '/kd-api/api/open/resources',
    <String, String>{'user_id': '8', 'name': resourceName},
  );
  static const int maxFiles = 24;
  static const int maxFileBytes = 20 * 1024 * 1024;

  static final MarketingCacheService instance = MarketingCacheService(
    cacheRoot: Directory(
      _join(
        PlatformStorageLayout.current().cacheDirectory,
        'Marketing/$resourceName',
      ),
    ),
  );

  final Directory cacheRoot;
  final MarketingManifestLoader _manifestLoader;
  final MarketingBytesLoader _bytesLoader;
  final ValueNotifier<MarketingCacheSnapshot> snapshot =
      ValueNotifier<MarketingCacheSnapshot>(
        const MarketingCacheSnapshot.loading(),
      );

  Timer? _startupTimer;
  Future<void>? _refreshing;
  bool _started = false;

  void start({Duration delay = const Duration(seconds: 3)}) {
    if (_started) return;
    _started = true;
    unawaited(loadCached());
    _startupTimer = Timer(delay, () => unawaited(refresh()));
  }

  void stop() {
    _startupTimer?.cancel();
    _startupTimer = null;
    _started = false;
  }

  Future<void> loadCached() async {
    final MarketingCacheSnapshot? active = await _readPointer('active.json');
    if (active != null) {
      snapshot.value = active;
      return;
    }
    final MarketingCacheSnapshot? backup = await _readPointer('backup.json');
    if (backup != null) snapshot.value = backup;
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    final MarketingCacheSnapshot previous = snapshot.value;
    snapshot.value = MarketingCacheSnapshot(
      state: MarketingCacheState.syncing,
      version: previous.version,
      images: previous.images,
    );
    try {
      await cacheRoot.create(recursive: true);
      final MarketingRemoteManifest manifest = await _manifestLoader();
      _validateManifest(manifest);
      final String manifestDigest = _manifestDigest(manifest);
      final Map<String, Object?>? activeJson = await _readJson(
        File(_join(cacheRoot.path, 'active.json')),
      );
      if (activeJson?['manifestDigest'] == manifestDigest) {
        final MarketingCacheSnapshot? active = await _readPointer(
          'active.json',
        );
        if (active != null) {
          snapshot.value = active;
          return;
        }
      }

      final String safeVersion = manifest.version.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final String directoryName =
          '$safeVersion-${manifestDigest.substring(0, 16)}';
      final Directory staging = Directory(
        _join(
          cacheRoot.path,
          '.staging-${DateTime.now().microsecondsSinceEpoch}-$pid',
        ),
      );
      await staging.create(recursive: true);
      final List<Map<String, Object?>> localFiles = <Map<String, Object?>>[];
      try {
        for (int index = 0; index < manifest.files.length; index += 1) {
          final MarketingRemoteFile remote = manifest.files[index];
          final Uint8List bytes = await _bytesLoader(remote);
          _validateBytes(remote, bytes);
          final String extension = switch (remote.mime) {
            'image/png' => 'png',
            'image/jpeg' => 'jpg',
            'image/webp' => 'webp',
            _ => throw const FormatException('unsupported image MIME'),
          };
          final String localName =
              '${index.toString().padLeft(2, '0')}-${remote.md5Digest}.$extension';
          await File(
            _join(staging.path, localName),
          ).writeAsBytes(bytes, flush: true);
          localFiles.add(<String, Object?>{
            'name': remote.name,
            'localName': localName,
            'mime': remote.mime,
            'md5': remote.md5Digest,
            'size': remote.size,
            'sortOrder': remote.sortOrder,
          });
        }
        await File(_join(staging.path, 'manifest.json')).writeAsString(
          jsonEncode(<String, Object?>{
            'resourceName': manifest.name,
            'version': manifest.version,
            'manifestDigest': manifestDigest,
            'files': localFiles,
          }),
          flush: true,
        );
        final Directory destination = Directory(
          _join(cacheRoot.path, directoryName),
        );
        if (await destination.exists()) {
          await destination.delete(recursive: true);
        }
        await staging.rename(destination.path);
      } catch (_) {
        if (await staging.exists()) await staging.delete(recursive: true);
        rethrow;
      }

      final File activeFile = File(_join(cacheRoot.path, 'active.json'));
      if (await activeFile.exists()) {
        final File backupTemporary = File(
          _join(
            cacheRoot.path,
            '.backup-${DateTime.now().microsecondsSinceEpoch}.tmp',
          ),
        );
        await activeFile.copy(backupTemporary.path);
        await AtomicFile.commit(
          backupTemporary,
          File(_join(cacheRoot.path, 'backup.json')),
        );
      }
      final File activeTemporary = File(
        _join(
          cacheRoot.path,
          '.active-${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      await activeTemporary.writeAsString(
        jsonEncode(<String, Object?>{
          'resourceName': manifest.name,
          'version': manifest.version,
          'manifestDigest': manifestDigest,
          'directory': directoryName,
          'files': localFiles,
        }),
        flush: true,
      );
      await AtomicFile.commit(activeTemporary, activeFile);
      final MarketingCacheSnapshot? active = await _readPointer('active.json');
      if (active == null) {
        throw const FormatException('published cache is invalid');
      }
      snapshot.value = active;
      await _cleanup(directoryName);
    } catch (error) {
      final MarketingCacheSnapshot? fallback =
          await _readPointer('active.json') ??
          await _readPointer('backup.json');
      snapshot.value =
          fallback ??
          (previous.hasImages
              ? MarketingCacheSnapshot(
                  state: MarketingCacheState.ready,
                  version: previous.version,
                  images: previous.images,
                  failureCategory: _failureCategory(error),
                )
              : MarketingCacheSnapshot(
                  state: MarketingCacheState.offline,
                  failureCategory: _failureCategory(error),
                ));
    }
  }

  Future<MarketingCacheSnapshot?> _readPointer(String name) async {
    final Map<String, Object?>? pointer = await _readJson(
      File(_join(cacheRoot.path, name)),
    );
    if (pointer == null || pointer['resourceName'] != resourceName) return null;
    final String version = '${pointer['version'] ?? ''}';
    final String directoryName = '${pointer['directory'] ?? ''}';
    final Object? rawFiles = pointer['files'];
    if (!_safeToken(version) ||
        !_safeToken(directoryName) ||
        rawFiles is! List) {
      return null;
    }
    final List<MarketingCachedImage> files = <MarketingCachedImage>[];
    for (final Object? raw in rawFiles) {
      if (raw is! Map<String, Object?>) return null;
      final String localName = '${raw['localName'] ?? ''}';
      final String expectedMd5 = '${raw['md5'] ?? ''}';
      final int? expectedSize = raw['size'] as int?;
      final int? sortOrder = raw['sortOrder'] as int?;
      if (!_safeToken(localName) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(expectedMd5) ||
          expectedSize == null ||
          sortOrder == null) {
        return null;
      }
      final File file = File(
        _join(cacheRoot.path, '$directoryName/$localName'),
      );
      if (!await file.exists()) return null;
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length != expectedSize ||
          md5.convert(bytes).toString() != expectedMd5) {
        return null;
      }
      if (image_codec.decodeImage(bytes) == null) return null;
      files.add(
        MarketingCachedImage(
          name: '${raw['name'] ?? '宣传图'}',
          path: file.path,
          sortOrder: sortOrder,
        ),
      );
    }
    if (files.isEmpty || files.length > maxFiles) return null;
    files.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return MarketingCacheSnapshot(
      state: MarketingCacheState.ready,
      version: version,
      images: List<MarketingCachedImage>.unmodifiable(files),
    );
  }

  Future<void> _cleanup(String activeDirectory) async {
    final Map<String, Object?>? backup = await _readJson(
      File(_join(cacheRoot.path, 'backup.json')),
    );
    final String backupDirectory = '${backup?['directory'] ?? ''}';
    await for (final FileSystemEntity entity in cacheRoot.list()) {
      if (entity is! Directory) continue;
      final String name = entity.path.replaceAll('\\', '/').split('/').last;
      if (name == activeDirectory || name == backupDirectory) continue;
      if (name.startsWith('.staging-') || _safeToken(name)) {
        await entity.delete(recursive: true);
      }
    }
  }

  static Future<MarketingRemoteManifest> _loadProductionManifest() async {
    final Uint8List body = await _getHttps(endpoint, maxBytes: 2 * 1024 * 1024);
    final Object? decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, Object?> || decoded['status'] != 200) {
      throw const FormatException('resource service rejected request');
    }
    final Object? data = decoded['data'];
    if (data is! Map<String, Object?> || data['files'] is! List) {
      throw const FormatException('resource manifest is malformed');
    }
    return MarketingRemoteManifest(
      name: '${data['name'] ?? resourceName}',
      version: '${data['version'] ?? ''}',
      files: (data['files']! as List<Object?>)
          .map((Object? raw) {
            if (raw is! Map<String, Object?>) {
              throw const FormatException('resource file is malformed');
            }
            return MarketingRemoteFile(
              name: '${raw['name'] ?? ''}',
              url: Uri.parse('${raw['url'] ?? ''}'),
              mime: '${raw['mime'] ?? ''}'.toLowerCase(),
              md5Digest: '${raw['md5'] ?? ''}'.toLowerCase(),
              size: raw['size'] is int ? raw['size']! as int : -1,
              sortOrder: raw['sort_order'] is int
                  ? raw['sort_order']! as int
                  : -1,
            );
          })
          .toList(growable: false),
    );
  }

  static Future<Uint8List> _loadProductionBytes(MarketingRemoteFile file) =>
      _getHttps(file.url, maxBytes: maxFileBytes);

  static Future<Uint8List> _getHttps(Uri uri, {required int maxBytes}) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('HTTPS is required');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      int total = 0;
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 20),
      )) {
        total += chunk.length;
        if (total > maxBytes) {
          throw const FormatException('resource exceeds size limit');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static void _validateManifest(MarketingRemoteManifest manifest) {
    if (manifest.name != resourceName || !_safeToken(manifest.version)) {
      throw const FormatException('resource identity is invalid');
    }
    if (manifest.files.isEmpty || manifest.files.length > maxFiles) {
      throw const FormatException('resource count is invalid');
    }
    final Set<String> names = <String>{};
    final Set<int> sortOrders = <int>{};
    for (final MarketingRemoteFile file in manifest.files) {
      if (!_safeFileName(file.name) || !names.add(file.name)) {
        throw const FormatException('resource name is invalid');
      }
      if (!sortOrders.add(file.sortOrder) || file.sortOrder < 0) {
        throw const FormatException('resource order is invalid');
      }
      if (file.url.scheme != 'https' || file.url.host.isEmpty) {
        throw const FormatException('resource URL must use HTTPS');
      }
      if (!const <String>{
            'image/png',
            'image/jpeg',
            'image/webp',
          }.contains(file.mime) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(file.md5Digest) ||
          file.size < 1 ||
          file.size > maxFileBytes) {
        throw const FormatException('resource metadata is invalid');
      }
    }
  }

  static void _validateBytes(MarketingRemoteFile file, Uint8List bytes) {
    if (bytes.length != file.size ||
        md5.convert(bytes).toString() != file.md5Digest) {
      throw const FormatException('resource integrity check failed');
    }
    final image_codec.Image? decoded = image_codec.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('resource image cannot be decoded');
    }
    final bool signatureMatches = switch (file.mime) {
      'image/png' =>
        bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47,
      'image/jpeg' => bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8,
      'image/webp' =>
        bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP',
      _ => false,
    };
    if (!signatureMatches) {
      throw const FormatException('resource MIME mismatch');
    }
  }

  static String _manifestDigest(MarketingRemoteManifest manifest) => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'name': manifest.name,
            'version': manifest.version,
            'files': manifest.files
                .map(
                  (file) => <String, Object?>{
                    'name': file.name,
                    'url': file.url.toString(),
                    'mime': file.mime,
                    'md5': file.md5Digest,
                    'size': file.size,
                    'sortOrder': file.sortOrder,
                  },
                )
                .toList(growable: false),
          }),
        ),
      )
      .toString();

  static Future<Map<String, Object?>?> _readJson(File file) async {
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static bool _safeToken(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

  static bool _safeFileName(String value) =>
      value.isNotEmpty &&
      value.length <= 160 &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\u0000');

  static String _failureCategory(Object error) => switch (error) {
    FormatException() => 'validation_failed',
    HttpException() => 'http_failed',
    SocketException() => 'network_failed',
    TimeoutException() => 'timeout',
    FileSystemException() => 'storage_failed',
    _ => 'unknown_failed',
  };

  static String _join(String left, String right) {
    final String separator = Platform.pathSeparator;
    return '${left.endsWith(separator) ? left.substring(0, left.length - 1) : left}$separator${right.replaceAll('/', separator)}';
  }
}
