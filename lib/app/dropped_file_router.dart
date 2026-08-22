import 'dart:io';
import 'dart:typed_data';

import '../features/archive/domain/archive_service.dart';
import '../features/documents/domain/format_router.dart';
import 'supported_file_types.dart';

enum DroppedFileRouteKind {
  archive,
  document,
  database,
  image,
  model,
  audio,
  rejected,
}

class DroppedFileRoute {
  const DroppedFileRoute({
    required this.path,
    required this.kind,
    required this.detail,
    this.documentMode,
  });

  final String path;
  final DroppedFileRouteKind kind;
  final String detail;
  final DocViewMode? documentMode;

  bool get canOpen => kind != DroppedFileRouteKind.rejected;
}

/// 对每个拖入项做轻量内容识别。只读取文件头，不静默跳过任何项目。
abstract final class DroppedFileRouter {
  static Future<DroppedFileRoute> classify(String rawPath) async {
    final String path = rawPath.trim();
    if (path.isEmpty) {
      return const DroppedFileRoute(
        path: '',
        kind: DroppedFileRouteKind.rejected,
        detail: '路径为空',
      );
    }
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.directory) {
      return DroppedFileRoute(
        path: path,
        kind: DroppedFileRouteKind.rejected,
        detail: '这是文件夹；请在重复文件或批量重命名工具中选择该目录',
      );
    }
    if (type != FileSystemEntityType.file) {
      return DroppedFileRoute(
        path: path,
        kind: DroppedFileRouteKind.rejected,
        detail: type == FileSystemEntityType.link
            ? '为避免越界访问，不自动跟随符号链接'
            : '文件不存在或无法访问',
      );
    }

    try {
      final File file = File(path);
      final VibekitsFileKind extensionKind = SupportedFileTypes.kindForPath(
        path,
      );
      if (extensionKind == VibekitsFileKind.model) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.model,
          detail: '已识别为本地模型，交给模型仓库校验并导入',
        );
      }
      if (extensionKind == VibekitsFileKind.audio) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.audio,
          detail: '已识别为 PCM/WAV，交给音频调试工具分析波形与信号质量',
        );
      }
      final int size = await file.length();
      // Known documents need only enough bytes to reject a misleading suffix
      // (ZIP/image/SQLite magic). Unknown archives still retain the larger
      // probe required by TAR/ISO signatures at fixed offsets.
      final int probeBytes = extensionKind == VibekitsFileKind.document
          ? 512
          : 0x9000;
      final RandomAccessFile reader = await file.open();
      late final Uint8List header;
      try {
        header = await reader.read(size.clamp(0, probeBytes));
      } finally {
        await reader.close();
      }

      final ArchiveFormat magicArchive = archiveFormatForBytes(header);
      if (magicArchive != ArchiveFormat.unsupported) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.archive,
          detail: '按文件头识别为 ${_archiveLabel(magicArchive)}',
        );
      }

      if (_isImageHeader(header)) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.image,
          detail: '已按文件内容识别为图片，自动预览并准备文字识别',
        );
      }

      if (_isSqliteHeader(header)) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.database,
          detail: '已按文件内容识别为 SQLite 数据库，自动只读打开',
        );
      }

      if (extensionKind == VibekitsFileKind.archive) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.archive,
          detail: '按扩展名交给解压缩工具验证',
        );
      }
      if (extensionKind == VibekitsFileKind.document) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.document,
          detail: '按扩展名交给文档阅读处理',
          documentMode: documentModeForPath(path),
        );
      }
      if (extensionKind == VibekitsFileKind.database) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.database,
          detail: '按扩展名交给 SQLite 数据库管理器验证并只读打开',
        );
      }
      if (extensionKind == VibekitsFileKind.image) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.image,
          detail: '已识别为图片，自动预览并准备文字识别',
        );
      }
      if (extensionKind == VibekitsFileKind.model) {
        return DroppedFileRoute(
          path: path,
          kind: DroppedFileRouteKind.model,
          detail: '已识别为本地模型，交给模型仓库校验并导入',
        );
      }

      final DocViewMode mode = documentModeForUnknownBytes(header);
      return DroppedFileRoute(
        path: path,
        kind: DroppedFileRouteKind.document,
        detail: mode == DocViewMode.text
            ? '未知扩展名，已按内容自动选择文本查看'
            : '未知扩展名，已按内容自动选择 Hex 查看',
        documentMode: mode,
      );
    } on FileSystemException catch (error) {
      return DroppedFileRoute(
        path: path,
        kind: DroppedFileRouteKind.rejected,
        detail: '读取失败：${error.message}',
      );
    }
  }

  static bool _isImageHeader(Uint8List bytes) {
    bool matches(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (int index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    if (matches(<int>[0x89, 0x50, 0x4e, 0x47]) ||
        matches(<int>[0xff, 0xd8, 0xff]) ||
        matches(<int>[0x47, 0x49, 0x46, 0x38]) ||
        matches(<int>[0x42, 0x4d]) ||
        matches(<int>[0x49, 0x49, 0x2a, 0x00]) ||
        matches(<int>[0x4d, 0x4d, 0x00, 0x2a]) ||
        matches(<int>[0x38, 0x42, 0x50, 0x53]) ||
        matches(<int>[0x76, 0x2f, 0x31, 0x01]) ||
        matches(<int>[0x01, 0x01, 0x00, 0x00]) ||
        matches(<int>[0x00, 0x00, 0x01, 0x00]) ||
        matches(<int>[0x00, 0x00, 0x02, 0x00])) {
      return true;
    }
    return bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  }

  static bool _isSqliteHeader(Uint8List bytes) {
    const List<int> signature = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (bytes.length < signature.length) return false;
    for (int index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static String _archiveLabel(ArchiveFormat format) => switch (format) {
    ArchiveFormat.zip => 'ZIP',
    ArchiveFormat.tar => 'TAR',
    ArchiveFormat.gzip => 'GZip',
    ArchiveFormat.bzip2 => 'BZip2',
    ArchiveFormat.xz => 'XZ',
    ArchiveFormat.sevenZip => '7z',
    ArchiveFormat.rar => 'RAR',
    ArchiveFormat.iso => 'ISO',
    ArchiveFormat.external => '7-Zip 兼容压缩格式',
    ArchiveFormat.unsupported => '未知压缩格式',
  };
}
