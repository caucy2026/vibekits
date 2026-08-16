import 'dart:io';

import 'package:vibekits/app/windows_file_associations.dart';

void main(List<String> arguments) {
  if (!Platform.isWindows || arguments.length != 1) {
    stderr.writeln('用法：dart run tool/register_file_types.dart <vibekits.exe>');
    exitCode = 64;
    return;
  }
  WindowsFileAssociations.registerExecutable(
    File(arguments.single).absolute.path,
    throwOnError: true,
  );
  stdout.writeln('Vibekits 文件类型已注册到当前用户。');
}
