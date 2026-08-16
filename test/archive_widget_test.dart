import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/presentation/archive_tab.dart';
import 'package:vibekits/features/archive/domain/seven_zip.dart';

void main() {
  testWidgets('创建压缩包可选择 ZIP、TAR 和 TAR.GZ', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ArchiveTab())),
    );

    await tester.tap(find.text('创建压缩包'));
    await tester.pumpAndSettle();

    expect(find.text('选择压缩格式'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);
    expect(find.text('TAR'), findsOneWidget);
    expect(find.text('TAR.GZ'), findsOneWidget);
  });

  testWidgets('拖入官方 RAR5 后直接显示条目而不是不支持提示', (WidgetTester tester) async {
    final String path =
        'C:${Platform.pathSeparator}fixtures${Platform.pathSeparator}rarlng.rar';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchiveTab(
            initialPath: path,
            headerReader: (_) async => Uint8List.fromList(<int>[
              0x52,
              0x61,
              0x72,
              0x21,
              0x1a,
              0x07,
              0x01,
              0x00,
            ]),
            nativeLister: (_) async => const <SevenZipEntry>[
              SevenZipEntry(
                name: 'Resources/RAR/rarext.aps',
                size: 165268,
                isDirectory: false,
              ),
            ],
          ),
        ),
      ),
    );
    for (
      int attempt = 0;
      attempt < 100 && find.textContaining('rarlng.rar').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.textContaining('rarlng.rar'), findsOneWidget);
    expect(find.textContaining('共 '), findsOneWidget);
    expect(find.textContaining('暂不支持'), findsNothing);
  });
}
