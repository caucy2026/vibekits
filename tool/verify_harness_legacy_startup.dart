import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vibekits/features/dev_tools/domain/harness_legacy_modules.dart';

/// Real official-runtime smoke test, isolated from all user profiles. No model
/// requests, credentials, LAN calls or destructive cleanup of user data.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected node executable and DSH CLI');
  }
  final root = await Directory.systemTemp.createTemp('vibekits-startup-proof-');
  final home = Directory('${root.path}/home')..createSync();
  final legacy = File(
    '${home.path}/profiles/node_modules/@deepseek-ai/dsh/package.json',
  );
  await legacy.parent.create(recursive: true);
  await legacy.writeAsString(
    jsonEncode({'name': '@deepseek-ai/dsh', 'version': '0.0.0'}),
  );

  Future<bool> boot({required bool expectConflict}) async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final process = await Process.start(
      args[0],
      ['--expose-internals', args[1], 'web', '--port', '$port', '--no-open'],
      workingDirectory: root.path,
      environment: {
        'DSH_HOME': home.path,
        'PATH': '${File(args[0]).parent.path}:/usr/bin:/bin',
      },
      includeParentEnvironment: false,
    );
    var conflict = false;
    final ready = Completer<Uri?>();
    final expected = Uri.parse('http://127.0.0.1:$port');
    void line(String value) {
      if (value.contains('not a symlink or dsh-managed module proxy')) {
        conflict = true;
      }
      final uri = harnessAnnouncedUrl(value, expected);
      if (uri != null && !ready.isCompleted) ready.complete(uri);
    }

    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(line);
    final err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(line);
    unawaited(
      process.exitCode.then((_) {
        if (!ready.isCompleted) ready.complete(null);
      }),
    );
    try {
      final uri = await ready.future.timeout(const Duration(seconds: 60));
      if (expectConflict) {
        await process.exitCode;
        // Drain delivered diagnostic lines before asserting the reason.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return uri == null && conflict;
      }
      if (uri == null) return false;
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        final status = response.statusCode;
        await response.drain<void>();
        return status >= 200 && status < 400;
      } finally {
        client.close(force: true);
      }
    } finally {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      await out.cancel();
      await err.cancel();
    }
  }

  final reproduced = await boot(expectConflict: true);
  if (!reproduced) {
    throw StateError('Expected startup conflict was not reproduced');
  }
  final moved = await migrateHarnessLegacyModules(home, args[1]);
  final recovered = await boot(expectConflict: false);
  final repeated = recovered && await boot(expectConflict: false);
  final result = {
    'conflictReproduced': reproduced,
    'backedUpPackages': moved.length,
    'startupAfterMigration': recovered,
    'secondStartup': repeated,
    'userDataModified': false,
    'modelRequests': 0,
    'runtime': args[1],
    'evidenceDirectory': root.path,
  };
  await File(
    '${root.path}/result.json',
  ).writeAsString(jsonEncode(result), flush: true);
  stdout.writeln(jsonEncode(result));
  if (!recovered || !repeated || moved.length != 1) exitCode = 1;
}
