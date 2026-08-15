import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// 模型描述（docs/00 §7.1）。
class ModelInfo {
  const ModelInfo({
    required this.fileName,
    required this.capability,
    required this.size,
    required this.sha256,
  });

  final String fileName;
  final String capability;
  final int size;
  final String sha256;

  String get shaPrefix => sha256.length > 12 ? sha256.substring(0, 12) : sha256;
}

/// 本地模型管理（docs/00 §7.2，AI-001～AI-004）。
///
/// 负责模型清单、导入、校验与删除；推理运行时（ONNX Runtime）属后续接入。
abstract final class ModelStore {
  static Future<String> sha256OfFile(String path) async {
    final List<int> bytes = await File(path).readAsBytes();
    return crypto.sha256.convert(bytes).toString();
  }

  static String sha256OfBytes(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  /// 列出模型目录中的文件。
  static List<ModelInfo> list(String directory) {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      return const <ModelInfo>[];
    }
    final List<ModelInfo> models = <ModelInfo>[];
    for (final FileSystemEntity entity in dir.listSync(followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.file) {
        final File file = File(entity.path);
        models.add(
          ModelInfo(
            fileName: file.uri.pathSegments.last,
            capability: _capabilityFor(file.uri.pathSegments.last),
            size: file.lengthSync(),
            sha256: '', // 列表时不计算，选中时再校验
          ),
        );
      }
    }
    return models;
  }

  static String _capabilityFor(String name) {
    final String lower = name.toLowerCase();
    if (lower.contains('ocr')) return 'OCR';
    if (lower.contains('asr') || lower.contains('vosk')) return 'ASR';
    if (lower.contains('tts') || lower.contains('piper')) return 'TTS';
    return '未知';
  }

  /// 导入模型文件到目录并计算 SHA-256。
  static Future<ModelInfo> import(String sourcePath, String directory) async {
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      throw const FileSystemException('源文件不存在');
    }
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final String name = source.uri.pathSegments.last;
    final File dest = File('${dir.path}${Platform.pathSeparator}$name');
    await source.copy(dest.path);
    final String sha = await sha256OfFile(dest.path);
    return ModelInfo(
      fileName: name,
      capability: _capabilityFor(name),
      size: dest.lengthSync(),
      sha256: sha,
    );
  }

  static bool delete(String path) {
    try {
      File(path).deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}
