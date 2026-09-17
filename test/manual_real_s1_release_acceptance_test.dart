import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_S1_ACCEPTANCE'] == '1';

  test(
    'records the S1 serial and HiV730 manifest baselines through Harness tools',
    () async {
      final adbPath =
          Platform.environment['VIBEKITS_REAL_S1_ADB']?.trim() ?? '';
      final evidenceRoot = Directory(
        Platform.environment['VIBEKITS_REAL_S1_EVIDENCE'] ??
            '${Directory.systemTemp.path}/vibekits-s1-acceptance',
      );
      expect(File(adbPath).existsSync(), isTrue);
      await evidenceRoot.create(recursive: true);
      final bridge = VibekitsHarnessToolBridge(adbExecutable: adbPath);

      Future<Map<String, Object?>> attempt(
        String toolId,
        Map<String, Object?> arguments,
      ) async {
        final result = await bridge.invoke(
          toolId: toolId,
          arguments: arguments,
          approve: (_) async => true,
        );
        return <String, Object?>{
          'toolId': toolId,
          'ok': result.ok,
          if (result.data != null) 'data': result.data,
          if (result.error != null) 'error': result.error,
        };
      }

      final serial = await attempt(
        VibekitsHarnessToolBridge.serialListPortsId,
        const <String, Object?>{},
      );
      final refs = await attempt(
        VibekitsHarnessToolBridge.gitListRemoteRefsId,
        <String, Object?>{
          'remoteUrl': 'http://172.21.16.194:8092/HiV730/manifest.git',
          'pattern': 'refs/heads/master',
          'timeoutSeconds': 15,
        },
      );
      Map<String, Object?>? manifest;
      if (refs['ok'] == true) {
        manifest = await attempt(
          VibekitsHarnessToolBridge.gitReadRemoteFileId,
          <String, Object?>{
            'remoteUrl': 'http://172.21.16.194:8092/HiV730/manifest.git',
            'ref': 'master',
            'path': 'default.xml',
            'maxBytes': 1048576,
            'timeoutSeconds': 30,
          },
        );
      }
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final evidence = File('${evidenceRoot.path}/baseline-$suffix.json');
      await evidence.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'protocol': VibekitsHarnessToolBridge.protocolVersion,
          'serial': serial,
          'manifestRefs': refs,
          'manifest': ?manifest,
        }),
        flush: true,
      );
      // ignore: avoid_print
      print('VIBEKITS_REAL_S1_BASELINE=${evidence.path}');
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_S1_ACCEPTANCE=1',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'installs and launches the exact release APK through Harness tools on S1',
    () async {
      final target =
          Platform.environment['VIBEKITS_REAL_S1_TARGET'] ??
          '192.168.3.63:5555';
      final apkPath =
          Platform.environment['VIBEKITS_REAL_S1_APK']?.trim() ?? '';
      final adbPath =
          Platform.environment['VIBEKITS_REAL_S1_ADB']?.trim() ?? '';
      final evidenceRoot = Directory(
        Platform.environment['VIBEKITS_REAL_S1_EVIDENCE'] ??
            '${Directory.systemTemp.path}/vibekits-s1-acceptance',
      );
      expect(File(apkPath).existsSync(), isTrue);
      expect(File(adbPath).existsSync(), isTrue);
      await evidenceRoot.create(recursive: true);

      final bridge = VibekitsHarnessToolBridge(adbExecutable: adbPath);
      Future<Map<String, Object?>> invoke(
        String toolId,
        Map<String, Object?> arguments,
      ) async {
        final result = await bridge.invoke(
          toolId: toolId,
          arguments: arguments,
          approve: (_) async => true,
        );
        expect(result.ok, isTrue, reason: '$toolId: ${result.error}');
        return result.data!;
      }

      Map<String, Object?> devices = await invoke(
        VibekitsHarnessToolBridge.adbListDevicesId,
        const <String, Object?>{},
      );
      var deviceRows = (devices['devices'] as List?) ?? const <Object?>[];
      if (!deviceRows.any(
        (row) =>
            row is Map && row['serial'] == target && row['state'] == 'device',
      )) {
        await invoke(VibekitsHarnessToolBridge.adbConnectId, <String, Object?>{
          'address': target,
        });
        devices = await invoke(
          VibekitsHarnessToolBridge.adbListDevicesId,
          const <String, Object?>{},
        );
        deviceRows = (devices['devices'] as List?) ?? const <Object?>[];
      }
      expect(
        deviceRows.any(
          (row) =>
              row is Map && row['serial'] == target && row['state'] == 'device',
        ),
        isTrue,
      );

      final identity = <String, String>{};
      for (final property in <String>[
        'ro.product.model',
        'ro.product.manufacturer',
        'ro.product.device',
        'ro.build.version.release',
      ]) {
        final response = await invoke(
          VibekitsHarnessToolBridge.adbCommandId,
          <String, Object?>{
            'serial': target,
            'arguments': <String>['shell', 'getprop', property],
          },
        );
        identity[property] = '${response['stdout'] ?? ''}'.trim();
      }
      expect(identity['ro.product.model']?.toLowerCase(), 'huanglong');
      expect(identity['ro.product.manufacturer'], 'HL2.0');
      expect(identity['ro.product.device'], 'hi3781v730');
      expect(identity['ro.build.version.release'], '12');

      final serialPorts = await invoke(
        VibekitsHarnessToolBridge.serialListPortsId,
        const <String, Object?>{},
      );

      final suffix = DateTime.now().microsecondsSinceEpoch;
      final upload = File('${evidenceRoot.path}/roundtrip-$suffix.txt');
      final download = File('${evidenceRoot.path}/roundtrip-$suffix.out.txt');
      final screenshot = File('${evidenceRoot.path}/screen-$suffix.png');
      final remote = '/sdcard/Download/vibekits-acceptance-$suffix.txt';
      final content = utf8.encode('VIBEKITS_S1_ACCEPTANCE_$suffix');
      await upload.writeAsBytes(content, flush: true);

      await invoke(VibekitsHarnessToolBridge.adbPushFileId, <String, Object?>{
        'serial': target,
        'localPath': upload.path,
        'remotePath': remote,
      });
      await invoke(VibekitsHarnessToolBridge.adbPullFileId, <String, Object?>{
        'serial': target,
        'remotePath': remote,
        'localPath': download.path,
        'overwrite': true,
      });
      await invoke(VibekitsHarnessToolBridge.adbScreenshotId, <String, Object?>{
        'serial': target,
        'localPath': screenshot.path,
        'overwrite': true,
      });
      await invoke(VibekitsHarnessToolBridge.adbShellId, <String, Object?>{
        'serial': target,
        'arguments': <String>['rm', '-f', remote],
      });
      expect(await download.readAsBytes(), content);
      expect(await screenshot.length(), greaterThan(64));

      final installedMetadata = await invoke(
        VibekitsHarnessToolBridge.adbShellId,
        <String, Object?>{
          'serial': target,
          'arguments': <String>[
            'dumpsys',
            'package',
            'com.vibekits.vibekits',
            '|',
            'grep',
            '-E',
            'versionName|versionCode|signatures|apkSigningVersion|SigningDetails',
          ],
        },
      );
      final preinstallEvidence = File(
        '${evidenceRoot.path}/preinstall-$suffix.json',
      );
      await preinstallEvidence.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'target': target,
          'package': 'com.vibekits.vibekits',
          'metadata': '${installedMetadata['stdout'] ?? ''}',
          'screenshotPath': screenshot.path,
        }),
        flush: true,
      );
      // ignore: avoid_print
      print('VIBEKITS_REAL_S1_PREINSTALL=${preinstallEvidence.path}');

      final installedMetadataText = '${installedMetadata['stdout'] ?? ''}';
      final alreadyExact =
          installedMetadataText.contains('versionName=1.9.0-dev.211') &&
          installedMetadataText.contains('versionCode=2211');
      if (!alreadyExact) {
        await invoke(
          VibekitsHarnessToolBridge.adbInstallApkId,
          <String, Object?>{
            'serial': target,
            'apkPath': apkPath,
            'replace': true,
          },
        );
      }
      final version = await invoke(
        VibekitsHarnessToolBridge.adbShellId,
        <String, Object?>{
          'serial': target,
          'arguments': <String>[
            'dumpsys',
            'package',
            'com.vibekits.vibekits',
            '|',
            'grep',
            '-E',
            'versionName|versionCode',
          ],
        },
      );
      expect('${version['stdout']}', contains('versionName=1.9.0-dev.211'));
      expect('${version['stdout']}', contains('versionCode=2211'));

      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': target,
        'arguments': <String>[
          'shell',
          'monkey',
          '-p',
          'com.vibekits.vibekits',
          '-c',
          'android.intent.category.LAUNCHER',
          '1',
        ],
      });
      await Future<void>.delayed(const Duration(seconds: 4));
      final process = await invoke(
        VibekitsHarnessToolBridge.adbCommandId,
        <String, Object?>{
          'serial': target,
          'arguments': <String>['shell', 'pidof', 'com.vibekits.vibekits'],
        },
      );
      expect('${process['stdout']}'.trim(), isNotEmpty);
      final postLaunchScreenshot = File(
        '${evidenceRoot.path}/screen-$suffix-post-launch.png',
      );
      await invoke(VibekitsHarnessToolBridge.adbScreenshotId, <String, Object?>{
        'serial': target,
        'localPath': postLaunchScreenshot.path,
        'overwrite': true,
      });
      expect(await postLaunchScreenshot.length(), greaterThan(64));
      final logcat = await invoke(
        VibekitsHarnessToolBridge.adbLogcatId,
        <String, Object?>{'serial': target, 'lines': 200},
      );

      final evidence = File('${evidenceRoot.path}/result-$suffix.json');
      await evidence.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'passed': true,
          'target': target,
          'identity': identity,
          'serialPorts': serialPorts['ports'],
          'packageVersion': '${version['stdout']}'.trim(),
          'installSkippedAsExactVersion': alreadyExact,
          'pid': '${process['stdout']}'.trim(),
          'logcatBytes': utf8.encode('${logcat['stdout'] ?? ''}').length,
          'roundTripBytes': content.length,
          'screenshotPath': screenshot.path,
          'screenshotBytes': await screenshot.length(),
          'postLaunchScreenshotPath': postLaunchScreenshot.path,
          'postLaunchScreenshotBytes': await postLaunchScreenshot.length(),
          'evidenceSource': 'vibekits-harness-tool-bridge',
        }),
        flush: true,
      );
      // ignore: avoid_print
      print('VIBEKITS_REAL_S1_ACCEPTANCE=${evidence.path}');
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_S1_ACCEPTANCE=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
