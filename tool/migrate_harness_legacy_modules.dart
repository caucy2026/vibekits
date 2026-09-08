import 'dart:io';
import 'package:vibekits/features/dev_tools/domain/harness_legacy_modules.dart';

/// Uses the same non-destructive migration as desktop startup.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart migrate_harness_legacy_modules.dart <DSH_HOME> <bundled-cli>',
    );
    exitCode = 64;
    return;
  }
  if (!await File(args[1]).exists()) {
    throw ArgumentError('Bundled CLI does not exist');
  }
  final moved = await migrateHarnessLegacyModules(Directory(args[0]), args[1]);
  stdout.writeln('Backed up ${moved.length} legacy packages.');
  for (final path in moved) {
    stdout.writeln(path);
  }
}
