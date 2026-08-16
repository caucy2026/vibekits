import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/atomic_file.dart';

void main() {
  test('原子提交可创建和替换目标文件', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vk_atomic_file',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final File destination = File('${directory.path}/target.txt');
    final File first = File('${directory.path}/first.part')
      ..writeAsStringSync('first');
    await AtomicFile.commit(first, destination);
    expect(destination.readAsStringSync(), 'first');
    expect(first.existsSync(), isFalse);

    final File second = File('${directory.path}/second.part')
      ..writeAsStringSync('second');
    await AtomicFile.commit(second, destination);
    expect(destination.readAsStringSync(), 'second');
    expect(second.existsSync(), isFalse);
  });
}
