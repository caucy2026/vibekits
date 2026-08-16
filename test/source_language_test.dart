import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/supported_file_types.dart';
import 'package:vibekits/features/documents/domain/format_router.dart';
import 'package:vibekits/features/documents/domain/source_language.dart';

void main() {
  test('常用语言、基础设施文件和无后缀工程文件都能识别', () {
    final Map<String, String> examples = <String, String>{
      'main.dart': 'Dart',
      'server.ts': 'TypeScript',
      'main.py': 'Python',
      'lib.rs': 'Rust',
      'main.go': 'Go',
      'infra.tf': 'Terraform',
      'schema.proto': 'Protocol Buffers',
      'Makefile': 'Makefile',
      'Jenkinsfile': 'Jenkins Pipeline',
      'CMakeLists.txt': 'CMake',
    };
    for (final MapEntry<String, String> entry in examples.entries) {
      expect(SourceLanguageCatalog.identify(entry.key)?.label, entry.value);
      expect(
        SupportedFileTypes.kindForPath(entry.key),
        VibekitsFileKind.document,
        reason: entry.key,
      );
      expect(documentModeForPath(entry.key), DocViewMode.text);
    }
  });

  test('无扩展名脚本按 shebang 识别且标记 Shell', () {
    final SourceLanguageInfo? bash = SourceLanguageCatalog.identify(
      'deploy',
      head: '#!/usr/bin/env bash\necho ok',
    );
    final SourceLanguageInfo? python = SourceLanguageCatalog.identify(
      'worker',
      head: '#!/usr/bin/python3\nprint(1)',
    );
    expect(bash?.label, 'Bash');
    expect(bash?.isShell, isTrue);
    expect(python?.label, 'Python');
  });
}
