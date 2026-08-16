import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/presentation/archive_tab.dart';

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
}
