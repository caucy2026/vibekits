import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/crypto_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  group('哈希', () {
    test('MD5 空串', () {
      expect(
        (CryptoTools.md5('') as ToolSuccess).output,
        'd41d8cd98f00b204e9800998ecf8427e',
      );
    });

    test('SHA-1 空串', () {
      expect(
        (CryptoTools.sha1('') as ToolSuccess).output,
        'da39a3ee5e6b4b0d3255bfef95601890afd80709',
      );
    });

    test('SHA-256 abc', () {
      expect(
        (CryptoTools.sha256('abc') as ToolSuccess).output,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('SHA-512 空串', () {
      expect(
        (CryptoTools.sha512('') as ToolSuccess).output,
        'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce'
        '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e',
      );
    });

    test('HMAC-SHA256 标准向量', () {
      expect(
        (CryptoTools.hmacSha256(
          'key',
          'The quick brown fox jumps over the lazy dog',
        ) as ToolSuccess).output,
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      );
    });
  });

  group('UUID v4', () {
    test('默认生成 1 个且格式正确', () {
      final String output = (CryptoTools.uuidV4('') as ToolSuccess).output;
      expect(
        output,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('按数量生成多行', () {
      final String output = (CryptoTools.uuidV4('3') as ToolSuccess).output;
      expect(output.split('\n').length, 3);
    });

    test('非法数量失败', () {
      expect(CryptoTools.uuidV4('0'), isA<ToolFailure>());
    });
  });

  group('随机密码', () {
    test('默认长度 16', () {
      final String output =
          (CryptoTools.randomPassword('') as ToolSuccess).output;
      expect(output.length, 16);
    });

    test('按指定长度生成', () {
      final String output =
          (CryptoTools.randomPassword('20') as ToolSuccess).output;
      expect(output.length, 20);
    });

    test('非法长度失败', () {
      expect(CryptoTools.randomPassword('3'), isA<ToolFailure>());
    });
  });
}
