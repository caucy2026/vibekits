/// HTML 清洗与 CSP 注入（docs/00 §5.4，DOC-201/202）。
abstract final class WebSanitize {
  static final RegExp _script = RegExp(
    r'<script\b[^>]*>.*?</script\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _frameBlock = RegExp(
    r'<(?:iframe|object|embed)\b[^>]*>.*?</(?:iframe|object|embed)\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _frameOpen = RegExp(
    r'<(?:iframe|object|embed)\b[^>]*/?>',
    caseSensitive: false,
  );
  static final RegExp _eventAttr = RegExp(
    '\\s+on[a-z]+\\s*=\\s*("[^"]*"|\'[^\']*\'|[^\\s>]+)',
    caseSensitive: false,
  );

  /// 移除脚本、iframe/object/embed 与事件属性。
  static String sanitize(String html) {
    return html
        .replaceAll(_script, '')
        .replaceAll(_frameBlock, '')
        .replaceAll(_frameOpen, '')
        .replaceAll(_eventAttr, '');
  }

  /// 注入严格 CSP，禁止脚本、网络与外部资源。
  static String injectCsp(String html) {
    const String policy =
        "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:";
    const String head =
        '<meta http-equiv="Content-Security-Policy" content="$policy">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">';
    final String lower = html.toLowerCase();
    final int headEnd = lower.indexOf('</head>');
    if (headEnd >= 0) {
      return html.substring(0, headEnd) + head + html.substring(headEnd);
    }
    return '<!doctype html><html><head>$head</head><body>$html</body></html>';
  }
}
