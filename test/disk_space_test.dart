import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/archive_service.dart';
import 'package:vibekits/features/archive/domain/disk_space.dart';

void main() {
  test('Windows 可读取目标磁盘可用空间', () {
    if (!Platform.isWindows) return;
    final int? available = DiskSpace.availableBytes(Directory.systemTemp.path);
    expect(available, isNotNull);
    expect(available, greaterThan(0));
    final DiskSpaceSnapshot? snapshot = DiskSpace.snapshot(
      Directory.systemTemp.path,
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.totalBytes, greaterThan(0));
    expect(snapshot.freeBytes, greaterThanOrEqualTo(snapshot.availableBytes));
    expect(snapshot.usedBytes + snapshot.freeBytes, snapshot.totalBytes);
  });

  test('解压前空间不足时不创建输出', () async {
    final Directory target = Directory.systemTemp.createTempSync(
      'vk_disk_full',
    );
    addTearDown(() => target.deleteSync(recursive: true));
    final ArchiveListing listing = ArchiveService.list(
      ArchiveService.createArchive(
        files: <(String, List<int>)>[
          ('a.txt', <int>[1, 2, 3]),
        ],
        format: ArchiveFormat.zip,
      ),
      'a.zip',
    );

    expect(
      () => ArchiveService.extractAsync(
        listing: listing,
        targetDir: target.path,
        selectedNames: <String>{'a.txt'},
        availableDiskBytes: (String _) => 0,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.listSync(), isEmpty);
  });
}
