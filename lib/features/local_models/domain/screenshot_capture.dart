import 'dart:io';

typedef ScreenshotCapture = Future<String?> Function(String outputDirectory);

abstract final class SystemScreenshotCapture {
  static Future<String?> captureRegion(String outputDirectory) async {
    final Directory directory = Directory(outputDirectory);
    await directory.create(recursive: true);
    final String outputPath =
        '${directory.path}'
        '${Platform.pathSeparator}vibekits_ocr_'
        '${DateTime.now().microsecondsSinceEpoch}.png';
    if (Platform.isWindows) {
      return _captureWindows(outputPath);
    }
    if (Platform.isMacOS) {
      final ProcessResult result = await Process.run('screencapture', <String>[
        '-i',
        '-x',
        outputPath,
      ], runInShell: false);
      return result.exitCode == 0 && File(outputPath).existsSync()
          ? outputPath
          : null;
    }
    throw UnsupportedError('截图 OCR 当前支持 Windows 和 macOS');
  }

  static Future<String?> _captureWindows(String outputPath) async {
    final String safePath = outputPath.replaceAll("'", "''");
    final String script = <String>[
      r'Add-Type -AssemblyName System.Windows.Forms',
      r'Add-Type -AssemblyName System.Drawing',
      r'[System.Windows.Forms.Clipboard]::Clear()',
      r"Start-Process explorer.exe 'ms-screenclip:'",
      r'for ($i = 0; $i -lt 480; $i++) {',
      r'  Start-Sleep -Milliseconds 250',
      r'  if ([System.Windows.Forms.Clipboard]::ContainsImage()) {',
      r'    $image = [System.Windows.Forms.Clipboard]::GetImage()',
      "    \$image.Save('$safePath', [System.Drawing.Imaging.ImageFormat]::Png)",
      r'    $image.Dispose()',
      r'    exit 0',
      r'  }',
      r'}',
      r'exit 2',
    ].join('; ');
    final ProcessResult result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ], runInShell: false);
    return result.exitCode == 0 && File(outputPath).existsSync()
        ? outputPath
        : null;
  }
}
