import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/api_request_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('API 工作区发送完整请求并显示响应', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiRequestSpec? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            apiExecute:
                (
                  ApiRequestSpec spec,
                  ApiRequestCancellation cancellation,
                ) async {
                  captured = spec;
                  return ApiResponseData(
                    statusCode: 201,
                    reasonPhrase: 'Created',
                    headers: const <String, List<String>>{
                      'content-type': <String>['application/json'],
                    },
                    body: '{"ok":true}',
                    bodyBytes: 11,
                    elapsed: const Duration(milliseconds: 42),
                    finalUrl: Uri.parse('https://example.com/items'),
                  );
                },
          ),
        ),
      ),
    );
    await tester.tap(find.text('API 调试').first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('api-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POST').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-url')),
      'https://example.com/items',
    );
    await tester.enterText(find.byKey(const Key('api-body')), '{"name":"x"}');
    await tester.tap(find.byKey(const Key('api-primary-action')));
    await tester.pumpAndSettle();

    expect(captured?.method, 'POST');
    expect(captured?.body, '{"name":"x"}');
    expect(captured?.maxResponseBytes, 5 * 1024 * 1024);
    expect(find.text('201 Created'), findsOneWidget);
    expect(find.textContaining('{"ok":true}'), findsOneWidget);
  });

  testWidgets('请求头格式错误不会调用网络执行器', (WidgetTester tester) async {
    bool executed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            apiExecute:
                (
                  ApiRequestSpec spec,
                  ApiRequestCancellation cancellation,
                ) async {
                  executed = true;
                  throw StateError('不应执行');
                },
          ),
        ),
      ),
    );
    await tester.tap(find.text('API 调试').first);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('api-headers')),
      'broken header',
    );
    await tester.tap(find.byKey(const Key('api-primary-action')));
    await tester.pump();
    expect(executed, isFalse);
    expect(find.byKey(const Key('api-error')), findsOneWidget);
  });
}
