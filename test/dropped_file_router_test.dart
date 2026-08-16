import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/dropped_file_router.dart';
import 'package:vibekits/features/documents/domain/format_router.dart';

void main() {
  test('未知文本和二进制文件都得到自动处理路由', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_route',
    );
    final File text = File('${sandbox.path}/notes.unknown')
      ..writeAsStringSync('hello\n你好');
    final File binary = File('${sandbox.path}/payload.data')
      ..writeAsBytesSync(<int>[0x00, 0x01, 0x02, 0xff]);
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final DroppedFileRoute textRoute = await DroppedFileRouter.classify(
      text.path,
    );
    final DroppedFileRoute binaryRoute = await DroppedFileRouter.classify(
      binary.path,
    );

    expect(textRoute.kind, DroppedFileRouteKind.document);
    expect(textRoute.documentMode, DocViewMode.text);
    expect(textRoute.detail, contains('自动选择文本'));
    expect(binaryRoute.kind, DroppedFileRouteKind.document);
    expect(binaryRoute.documentMode, DocViewMode.hex);
    expect(binaryRoute.detail, contains('自动选择 Hex'));
  });

  test('错误扩展名的压缩文件按文件头优先路由', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_magic',
    );
    final File disguised = File('${sandbox.path}/archive.txt')
      ..writeAsBytesSync(<int>[0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]);
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final DroppedFileRoute route = await DroppedFileRouter.classify(
      disguised.path,
    );

    expect(route.kind, DroppedFileRouteKind.archive);
    expect(route.detail, contains('ZIP'));
  });

  test('文件夹和不存在路径返回明确结果而非静默忽略', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_reject',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final DroppedFileRoute directory = await DroppedFileRouter.classify(
      sandbox.path,
    );
    final DroppedFileRoute missing = await DroppedFileRouter.classify(
      '${sandbox.path}/missing.file',
    );

    expect(directory.kind, DroppedFileRouteKind.rejected);
    expect(directory.detail, contains('文件夹'));
    expect(missing.kind, DroppedFileRouteKind.rejected);
    expect(missing.detail, contains('不存在'));
  });

  test('模型文件自动交给本地模型仓库', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_model',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File model = File('${sandbox.path}${Platform.pathSeparator}tiny.onnx')
      ..writeAsBytesSync(<int>[8, 7, 6, 5]);
    final DroppedFileRoute route = await DroppedFileRouter.classify(model.path);
    expect(route.kind, DroppedFileRouteKind.model);
    expect(route.detail, contains('模型'));
  });

  test('图片即使扩展名错误也按文件头进入预览与 OCR', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_image',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File image = File('${sandbox.path}${Platform.pathSeparator}photo.bin')
      ..writeAsBytesSync(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

    final DroppedFileRoute route = await DroppedFileRouter.classify(image.path);
    expect(route.kind, DroppedFileRouteKind.image);
    expect(route.detail, contains('自动预览'));
  });

  test('SQLite 即使扩展名错误也按文件头只读打开', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_drop_sqlite',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File database =
        File('${sandbox.path}${Platform.pathSeparator}records.data')
          ..writeAsBytesSync(<int>[
            ...'SQLite format 3'.codeUnits,
            0,
            ...List<int>.filled(84, 0),
          ]);

    final DroppedFileRoute route = await DroppedFileRouter.classify(
      database.path,
    );
    expect(route.kind, DroppedFileRouteKind.database);
    expect(route.detail, contains('只读打开'));
  });
}
