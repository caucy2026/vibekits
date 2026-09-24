import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lan_harness_key_receiver.dart';

void main() {
  test('二维码页只接收一次 Key 且二维码本身不包含 Key', () async {
    final LanHarnessKeyReceiver receiver = await LanHarnessKeyReceiver.start(
      lifetime: const Duration(seconds: 10),
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(receiver.close);
    expect(receiver.pageUri.toString(), isNot(contains('sk-test')));

    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));
    final HttpClientRequest pageRequest = await client.getUrl(receiver.pageUri);
    final HttpClientResponse pageResponse = await pageRequest.close();
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(
      await pageResponse.transform(utf8.decoder).join(),
      contains('确认授权并发送到 Pad'),
    );

    final HttpClientRequest submit = await client.postUrl(receiver.pageUri);
    submit.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    submit.write(
      Uri(queryParameters: <String, String>{'apiKey': 'sk-test-123456'}).query,
    );
    final HttpClientResponse submitResponse = await submit.close();
    expect(submitResponse.statusCode, HttpStatus.ok);
    await submitResponse.drain<void>();
    expect(await receiver.keyReceived, 'sk-test-123456');
  });

  test('错误令牌不能读取页面', () async {
    final LanHarnessKeyReceiver receiver = await LanHarnessKeyReceiver.start(
      lifetime: const Duration(seconds: 10),
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(receiver.close);
    final Uri invalid = receiver.pageUri.replace(
      queryParameters: <String, String>{'token': 'wrong'},
    );
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));
    final HttpClientResponse response = await (await client.getUrl(
      invalid,
    )).close();
    expect(response.statusCode, HttpStatus.notFound);
  });

  test('手机扫码页面只接收一次 HTTPS 订阅地址', () async {
    final LanHarnessKeyReceiver receiver = await LanHarnessKeyReceiver.start(
      kind: LanInputKind.subscription,
      lifetime: const Duration(seconds: 10),
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(receiver.close);
    expect(receiver.pageUri.path, '/subscription');
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));
    final HttpClientResponse page = await (await client.getUrl(
      receiver.pageUri,
    )).close();
    expect(await page.transform(utf8.decoder).join(), contains('输入代理订阅'));

    Future<int> post(String value) async {
      final HttpClientRequest request = await client.postUrl(receiver.pageUri);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        Uri(queryParameters: <String, String>{'subscriptionUrl': value}).query,
      );
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await post('http://example.com/config'), HttpStatus.badRequest);
    const String url = 'https://example.com/subscription?token=secret';
    expect(await post(url), HttpStatus.ok);
    expect(await receiver.valueReceived, url);
    expect(receiver.pageUri.toString(), isNot(contains('secret')));
  });
}
