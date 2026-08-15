import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/encoding_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  group('Base64', () {
    test('编码', () {
      expect(EncodingTools.base64Encode('Hello'), isA<ToolSuccess>());
      expect(
        (EncodingTools.base64Encode('Hello') as ToolSuccess).output,
        'SGVsbG8=',
      );
    });

    test('解码', () {
      expect(
        (EncodingTools.base64Decode('SGVsbG8=') as ToolSuccess).output,
        'Hello',
      );
    });

    test('非法输入返回失败', () {
      expect(EncodingTools.base64Decode('!!!'), isA<ToolFailure>());
    });
  });

  group('URL', () {
    test('编码与解码', () {
      const String encoded = 'a%20b%26c';
      expect((EncodingTools.urlEncode('a b&c') as ToolSuccess).output, encoded);
      expect((EncodingTools.urlDecode(encoded) as ToolSuccess).output, 'a b&c');
    });

    test('非法百分号返回失败', () {
      expect(EncodingTools.urlDecode('%zz'), isA<ToolFailure>());
    });
  });

  group('HTML 实体', () {
    test('编码', () {
      expect(
        (EncodingTools.htmlEncode('<a>') as ToolSuccess).output,
        '&lt;a&gt;',
      );
    });

    test('解码含数字实体', () {
      expect(
        (EncodingTools.htmlDecode('&lt;&#65;&amp;') as ToolSuccess).output,
        '<A&',
      );
    });
  });

  group('Unicode 转义', () {
    test('编码与反转义', () {
      const String text = 'A中';
      final String escaped =
          (EncodingTools.unicodeEscape(text) as ToolSuccess).output;
      expect(escaped, r'A\u4e2d');
      expect(
        (EncodingTools.unicodeUnescape(escaped) as ToolSuccess).output,
        text,
      );
    });
  });

  group('Hex', () {
    test('编码', () {
      expect((EncodingTools.hexEncode('A') as ToolSuccess).output, '41');
    });

    test('解码', () {
      expect((EncodingTools.hexDecode('41 42') as ToolSuccess).output, 'AB');
    });

    test('奇数长度失败', () {
      expect(EncodingTools.hexDecode('4'), isA<ToolFailure>());
    });

    test('非法字符失败', () {
      expect(EncodingTools.hexDecode('4g'), isA<ToolFailure>());
    });
  });

  group('进制转换', () {
    test('二进制转十六进制', () {
      expect(
        (EncodingTools.baseConvert('1111', '2', '16') as ToolSuccess).output,
        'f',
      );
    });

    test('非法进制失败', () {
      expect(EncodingTools.baseConvert('10', '2', '40'), isA<ToolFailure>());
    });
  });
}
