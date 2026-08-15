import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/svg_source.dart';
import 'package:vibekits/features/documents/domain/web_sanitize.dart';

void main() {
  test('HTML 清洗移除脚本与事件属性', () {
    const String html =
        '<html><body><p onclick="x()">hi</p><script>bad()</script><iframe src="a"></iframe></body></html>';
    final String clean = WebSanitize.sanitize(html);
    expect(clean, isNot(contains('script')));
    expect(clean, isNot(contains('iframe')));
    expect(clean, isNot(contains('onclick')));
    expect(clean, contains('<p'));
  });

  test('CSP 注入', () {
    const String html = '<html><head></head><body>x</body></html>';
    final String out = WebSanitize.injectCsp(html);
    expect(out, contains('Content-Security-Policy'));
    expect(out, contains("default-src 'none'"));
  });

  test('SVG 解码', () {
    final String text = SvgSource.decode(
      Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      ),
      compressed: false,
    );
    expect(text, contains('<svg'));
  });

  test('SVGZ 解压', () {
    final Uint8List raw = Uint8List.fromList(utf8.encode('<svg></svg>'));
    final Uint8List gz = Uint8List.fromList(GZipEncoder().encode(raw));
    final String text = SvgSource.decode(gz, compressed: true);
    expect(text, contains('<svg'));
  });
}
