import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test(
    'PAD63 exact candidate install and launch through Harness bridge',
    () async {
      final env = Platform.environment;
      final bridge = VibekitsHarnessToolBridge(
        adbExecutable: env['PAD63_ADB']!,
      );
      addTearDown(bridge.dispose);
      final evidence = Directory(env['PAD63_EVIDENCE']!);
      await evidence.create(recursive: true);
      const target = '192.168.3.63:5555';
      final records = <Object?>[];
      Future<Map<String, Object?>> call(
        String id,
        Map<String, Object?> args,
      ) async {
        final r = await bridge.invoke(
          toolId: id,
          arguments: args,
          approve: (_) async => true,
        );
        records.add({'tool': id, 'result': r.toJson()});
        await File(
          '${evidence.path}/pad63-results.json',
        ).writeAsString(jsonEncode(records));
        expect(r.ok, isTrue, reason: '$id: ${r.error}');
        return r.data!;
      }

      Future<String> shell(List<String> args) async {
        final r = await call(VibekitsHarnessToolBridge.adbCommandId, {
          'serial': target,
          'arguments': ['shell', ...args],
        });
        return '${r['stdout'] ?? ''}';
      }

      await call(VibekitsHarnessToolBridge.adbConnectId, {'address': target});
      final identity = await shell(['getprop', 'ro.product.model']);
      expect(identity.trim(), isNotEmpty);
      expect(
        (await shell(['getprop', 'ro.product.device'])).trim(),
        'hi3781v730',
      );
      await shell(['getprop', 'ro.build.version.release']);
      await shell(['dumpsys', 'package', 'com.vibekits.vibekits']);
      final apk = env['PAD63_APK'];
      if (apk == null || apk.isEmpty) return;
      await call(VibekitsHarnessToolBridge.adbInstallApkId, {
        'serial': target,
        'apkPath': apk,
        'replace': true,
      });
      final version = await shell([
        'dumpsys',
        'package',
        'com.vibekits.vibekits',
      ]);
      expect(version, contains('versionName=1.9.0-dev.225'));
      expect(version, contains('versionCode=2225'));
      await shell(['am', 'force-stop', 'com.vibekits.vibekits']);
      await shell([
        'monkey',
        '-p',
        'com.vibekits.vibekits',
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ]);
      await Future<void>.delayed(const Duration(seconds: 4));
      final process = (await shell(['pidof', 'com.vibekits.vibekits'])).trim();
      expect(process, isNotEmpty);
      await call(VibekitsHarnessToolBridge.adbScreenshotId, {
        'serial': target,
        'localPath': '${evidence.path}/pad63.png',
        'overwrite': true,
      });
      final log = await shell(['logcat', '-d', '--pid=$process', '-t', '200']);
      expect(log, isNot(contains('FATAL EXCEPTION')));
      expect(log, isNot(contains('Fatal signal')));
    },
    skip: Platform.environment['PAD63_RUN'] != '1',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
