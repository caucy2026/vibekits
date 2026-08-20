import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/disk_volume_discovery.dart';

void main() {
  test('列出当前终端可用磁盘及容量并标记系统盘', () async {
    final List<DiskVolumeInfo> volumes = await DiskVolumeDiscovery.discover();

    expect(volumes, isNotEmpty);
    expect(volumes.any((DiskVolumeInfo item) => item.isSystemVolume), isTrue);
    expect(
      volumes.every(
        (DiskVolumeInfo item) =>
            item.rootPath.isNotEmpty &&
            item.totalBytes > 0 &&
            item.freeBytes >= 0 &&
            item.freeBytes <= item.totalBytes,
      ),
      isTrue,
    );
    if (Platform.isWindows) {
      expect(
        volumes.every(
          (DiskVolumeInfo item) =>
              RegExp(r'^[A-Z]:\\$').hasMatch(item.rootPath),
        ),
        isTrue,
      );
    }
  });
}
