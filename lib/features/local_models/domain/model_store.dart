import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// 模型描述（docs/00 §7.1）。
enum ModelIntegrity { verified, modified, untracked }

class ModelInfo {
  const ModelInfo({
    required this.fileName,
    required this.capability,
    required this.size,
    required this.sha256,
    this.integrity = ModelIntegrity.untracked,
  });

  final String fileName;
  final String capability;
  final int size;
  final String sha256;
  final ModelIntegrity integrity;

  String get shaPrefix => sha256.length > 12 ? sha256.substring(0, 12) : sha256;
}

/// 本地模型管理（docs/00 §7.2，AI-001～AI-004）。
///
/// 负责模型清单、导入、校验与删除；推理运行时（ONNX Runtime）属后续接入。
abstract final class ModelStore {
  static const int maxModelBytes = 100 * 1024 * 1024;
  static const String _manifestName = '.vibekits-models.json';

  static Future<String> sha256OfFile(String path) async {
    return (await crypto.sha256.bind(File(path).openRead()).first).toString();
  }

  static String sha256OfBytes(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  /// 列出模型目录中的文件。
  static Future<List<ModelInfo>> list(String directory) async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      return const <ModelInfo>[];
    }
    final Map<String, Object?> manifest = await _readManifest(dir);
    final List<ModelInfo> models = <ModelInfo>[];
    await for (final FileSystemEntity entity in dir.list(followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.file) {
        final File file = File(entity.path);
        final String name = file.uri.pathSegments.last;
        if (name == _manifestName || name.endsWith('.part')) continue;
        final int size = await file.length();
        final String sha = await sha256OfFile(file.path);
        final Object? record = manifest[name];
        final String? expectedSha = record is Map<String, Object?>
            ? record['sha256'] as String?
            : null;
        final int? expectedSize = record is Map<String, Object?>
            ? record['size'] as int?
            : null;
        models.add(
          ModelInfo(
            fileName: name,
            capability: _capabilityFor(name),
            size: size,
            sha256: sha,
            integrity: expectedSha == null
                ? ModelIntegrity.untracked
                : expectedSha == sha && expectedSize == size
                ? ModelIntegrity.verified
                : ModelIntegrity.modified,
          ),
        );
      }
    }
    return models;
  }

  static String _capabilityFor(String name) {
    final String lower = name.toLowerCase();
    if (lower.contains('vad') || lower.contains('silero')) return 'VAD';
    if (lower.contains('ocr')) return 'OCR';
    if (lower.contains('asr') || lower.contains('vosk')) return 'ASR';
    if (lower.contains('tts') || lower.contains('piper')) return 'TTS';
    return '未知';
  }

  /// 导入模型文件到目录并计算 SHA-256。
  static Future<ModelInfo> import(
    String sourcePath,
    String directory, {
    int maxBytes = maxModelBytes,
  }) async {
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      throw const FileSystemException('源文件不存在');
    }
    final int sourceSize = await source.length();
    if (sourceSize > maxBytes) {
      throw FormatException('模型超过 ${maxBytes ~/ 1024 ~/ 1024}MB 上限');
    }
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final String name = source.uri.pathSegments.last;
    final File dest = File('${dir.path}${Platform.pathSeparator}$name');
    final File temporary = File('${dest.path}.part');
    try {
      await source.openRead().pipe(temporary.openWrite());
      final String sha = await sha256OfFile(temporary.path);
      if (await dest.exists()) await dest.delete();
      await temporary.rename(dest.path);
      final Map<String, Object?> manifest = await _readManifest(dir);
      manifest[name] = <String, Object>{'sha256': sha, 'size': sourceSize};
      await _writeManifest(dir, manifest);
      return ModelInfo(
        fileName: name,
        capability: _capabilityFor(name),
        size: sourceSize,
        sha256: sha,
        integrity: ModelIntegrity.verified,
      );
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static bool delete(String path) {
    try {
      final File file = File(path);
      final Directory directory = file.parent;
      final String name = file.uri.pathSegments.last;
      file.deleteSync();
      final Map<String, Object?> manifest = _readManifestSync(directory);
      manifest.remove(name);
      _writeManifestSync(directory, manifest);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, Object?>> _readManifest(Directory directory) async {
    try {
      final Object? value = jsonDecode(
        await File('${directory.path}${Platform.pathSeparator}$_manifestName')
            .readAsString(),
      );
      return value is Map<String, Object?> ? value : <String, Object?>{};
    } on Object {
      return <String, Object?>{};
    }
  }

  static Map<String, Object?> _readManifestSync(Directory directory) {
    try {
      final Object? value = jsonDecode(
        File('${directory.path}${Platform.pathSeparator}$_manifestName')
            .readAsStringSync(),
      );
      return value is Map<String, Object?> ? value : <String, Object?>{};
    } on Object {
      return <String, Object?>{};
    }
  }

  static Future<void> _writeManifest(
    Directory directory,
    Map<String, Object?> manifest,
  ) async {
    final File target = File(
      '${directory.path}${Platform.pathSeparator}$_manifestName',
    );
    final File temporary = File('${target.path}.part');
    await temporary.writeAsString(jsonEncode(manifest), flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  static void _writeManifestSync(
    Directory directory,
    Map<String, Object?> manifest,
  ) {
    final File target = File(
      '${directory.path}${Platform.pathSeparator}$_manifestName',
    );
    final File temporary = File('${target.path}.part');
    temporary.writeAsStringSync(jsonEncode(manifest), flush: true);
    if (target.existsSync()) target.deleteSync();
    temporary.renameSync(target.path);
  }
}
