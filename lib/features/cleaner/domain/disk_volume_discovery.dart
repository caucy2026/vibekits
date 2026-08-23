import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../archive/domain/disk_space.dart';
import 'cleanup_platform_policy.dart';

typedef _GetLogicalDrivesNative = Uint32 Function();
typedef _GetLogicalDrivesDart = int Function();
typedef _GetDriveTypeWNative = Uint32 Function(Pointer<Utf16> rootPathName);
typedef _GetDriveTypeWDart = int Function(Pointer<Utf16> rootPathName);

enum DiskVolumeType {
  fixed('本地磁盘'),
  removable('可移动磁盘'),
  network('网络磁盘'),
  ram('内存磁盘'),
  mounted('已挂载磁盘');

  const DiskVolumeType(this.label);

  final String label;
}

class DiskVolumeInfo {
  const DiskVolumeInfo({
    required this.rootPath,
    required this.name,
    required this.type,
    required this.totalBytes,
    required this.freeBytes,
    required this.availableBytes,
    required this.isSystemVolume,
  });

  final String rootPath;
  final String name;
  final DiskVolumeType type;
  final int totalBytes;
  final int freeBytes;
  final int availableBytes;
  final bool isSystemVolume;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
  double get usedRatio => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

abstract final class DiskVolumeDiscovery {
  static Future<List<DiskVolumeInfo>> discover({
    CleanupPlatform? platform,
  }) async {
    final CleanupPlatform targetPlatform = platform ?? CleanupPlatform.current;
    if (targetPlatform == CleanupPlatform.windows && Platform.isWindows) {
      return Isolate.run<List<DiskVolumeInfo>>(
        _discoverWindows,
        debugName: 'vibekits-disk-volume-discovery',
      );
    }
    if (targetPlatform == CleanupPlatform.macos) return _discoverUnix();
    if (targetPlatform == CleanupPlatform.android) {
      final String root = Directory.systemTemp.path;
      final DiskSpaceSnapshot? disk = DiskSpace.snapshot(root);
      if (disk == null) return const <DiskVolumeInfo>[];
      return <DiskVolumeInfo>[
        DiskVolumeInfo(
          rootPath: root,
          name: 'Vibekits 应用存储',
          type: DiskVolumeType.mounted,
          totalBytes: disk.totalBytes,
          freeBytes: disk.freeBytes,
          availableBytes: disk.availableBytes,
          isSystemVolume: false,
        ),
      ];
    }
    return const <DiskVolumeInfo>[];
  }

  static List<DiskVolumeInfo> _discoverWindows() {
    final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
    final _GetLogicalDrivesDart getLogicalDrives = kernel
        .lookupFunction<_GetLogicalDrivesNative, _GetLogicalDrivesDart>(
          'GetLogicalDrives',
        );
    final _GetDriveTypeWDart getDriveType = kernel
        .lookupFunction<_GetDriveTypeWNative, _GetDriveTypeWDart>(
          'GetDriveTypeW',
        );
    final int mask = getLogicalDrives();
    final String systemRoot = _systemRoot();
    final List<DiskVolumeInfo> volumes = <DiskVolumeInfo>[];
    for (int index = 0; index < 26; index++) {
      if (mask & (1 << index) == 0) continue;
      final String letter = String.fromCharCode(65 + index);
      final String root = '$letter:\\';
      final Pointer<Utf16> nativeRoot = root.toNativeUtf16();
      final int nativeType;
      try {
        nativeType = getDriveType(nativeRoot);
      } finally {
        malloc.free(nativeRoot);
      }
      final DiskVolumeType? type = switch (nativeType) {
        2 => DiskVolumeType.removable,
        3 => DiskVolumeType.fixed,
        4 => DiskVolumeType.network,
        6 => DiskVolumeType.ram,
        _ => null,
      };
      if (type == null) continue;
      final DiskSpaceSnapshot? disk = DiskSpace.snapshot(root);
      if (disk == null || disk.totalBytes <= 0) continue;
      final bool system = _sameRoot(root, systemRoot);
      volumes.add(
        DiskVolumeInfo(
          rootPath: root,
          name: '$letter:${system ? '（系统盘）' : ''}',
          type: type,
          totalBytes: disk.totalBytes,
          freeBytes: disk.freeBytes,
          availableBytes: disk.availableBytes,
          isSystemVolume: system,
        ),
      );
    }
    volumes.sort((DiskVolumeInfo left, DiskVolumeInfo right) {
      if (left.isSystemVolume != right.isSystemVolume) {
        return left.isSystemVolume ? -1 : 1;
      }
      return left.rootPath.compareTo(right.rootPath);
    });
    return volumes;
  }

  static Future<List<DiskVolumeInfo>> _discoverUnix() async {
    final ProcessResult result = await Process.run('df', <String>['-kP']);
    if (result.exitCode != 0) return const <DiskVolumeInfo>[];
    final Map<String, DiskVolumeInfo> volumes = <String, DiskVolumeInfo>{};
    final List<String> lines = '${result.stdout}'.split(RegExp(r'\r?\n'));
    for (final String line in lines.skip(1)) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 6) continue;
      final String mount = fields.sublist(5).join(' ');
      if (mount != '/' && !mount.startsWith('/Volumes/')) continue;
      final int? totalKb = int.tryParse(fields[1]);
      final int? availableKb = int.tryParse(fields[3]);
      if (totalKb == null || availableKb == null || totalKb <= 0) continue;
      final bool system = mount == '/';
      volumes[mount] = DiskVolumeInfo(
        rootPath: mount,
        name: system ? '/（系统盘）' : mount.split('/').last,
        type: DiskVolumeType.mounted,
        totalBytes: totalKb * 1024,
        freeBytes: availableKb * 1024,
        availableBytes: availableKb * 1024,
        isSystemVolume: system,
      );
    }
    return volumes.values.toList(growable: false)
      ..sort((DiskVolumeInfo left, DiskVolumeInfo right) {
        if (left.isSystemVolume != right.isSystemVolume) {
          return left.isSystemVolume ? -1 : 1;
        }
        return left.rootPath.compareTo(right.rootPath);
      });
  }

  static String _systemRoot() {
    final String? systemDrive = Platform.environment['SystemDrive'];
    if (systemDrive != null && systemDrive.trim().isNotEmpty) {
      return systemDrive.endsWith('\\') ? systemDrive : '$systemDrive\\';
    }
    final String? windows = Platform.environment['WINDIR'];
    return windows != null && windows.length >= 3
        ? windows.substring(0, 3)
        : 'C:\\';
  }

  static bool _sameRoot(String left, String right) =>
      left.replaceAll('/', '\\').toLowerCase() ==
      right.replaceAll('/', '\\').toLowerCase();
}
