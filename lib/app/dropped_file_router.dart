import 'dart:io';
import 'dart:typed_data';

import '../features/archive/domain/archive_service.dart';
import '../features/documents/domain/format_router.dart';
import 'supported_file_types.dart';

enum DroppedFileRouteKind { archive, document, model, rejected }

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
    final FileSystemEntityType type = FileSystemEntity.typeSync(
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
      final int size = await file.length();
      final RandomAccessFile reader = await file.open();
      late final Uint8List header;
      try {
        header = await reader.read(size.clamp(0, 0x9000));
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

      final VibekitsFileKind extensionKind = SupportedFileTypes.kindForPath(
        path,
      );
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

  static String _archiveLabel(ArchiveFormat format) => switch (format) {
    ArchiveFormat.zip => 'ZIP',
    ArchiveFormat.tar => 'TAR',
    ArchiveFormat.gzip => 'GZip',
    ArchiveFormat.bzip2 => 'BZip2',
    ArchiveFormat.xz => 'XZ',
    ArchiveFormat.sevenZip => '7z',
    ArchiveFormat.rar => 'RAR（当前仅识别）',
    ArchiveFormat.iso => 'ISO（当前仅识别）',
    ArchiveFormat.unsupported => '未知压缩格式',
  };
}
