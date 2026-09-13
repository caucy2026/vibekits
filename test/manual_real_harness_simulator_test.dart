import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final bool enabled =
      Platform.environment['VIBEKITS_REAL_REMOTE_SIMULATOR'] == '1';

  test(
    'real ID simulator lists tools and runs a read-only process probe',
    () async {
      final String executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final String routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final bool forceRelay =
          Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1';
      final bool enableAssistance =
          Platform.environment['VIBEKITS_REAL_REMOTE_ENABLE_ASSISTANCE'] == '1';
      expect(File(executable).existsSync(), isTrue);

      final RustDeskHostInfo host =
          await RustDeskHarnessShareService.ensureHostAvailable(
            configuredExecutable: executable,
          );
      final HarnessSimulatorController controller = HarnessSimulatorController(
        resolveHost: () async => host,
      );
      addTearDown(controller.closeAll);

      final Map<String, Object?> connected = await controller.connect(
        routingId,
        forceRelay: forceRelay,
      );
      expect(connected['connected'], isTrue);
      final List<Map<String, Object?>> tools = controller.catalog(routingId);
      expect(tools.length, greaterThan(100));
      expect(
        tools.any(
          (Map<String, Object?> item) =>
              item['name'] == 'vibekits.device.processes',
        ),
        isTrue,
      );
      final Map<String, Object?> result = await controller.call(
        routingId,
        'vibekits.device.processes',
        const <String, Object?>{'query': 'Vibekits'},
      );
      expect(result, isNotEmpty);
      final Map<String, Object?> sshProbe = await controller.runSshCommand(
        routingId,
        'printf VIBEKITS_SIMULATOR_SSH_READY',
      );
      expect(sshProbe['ok'], isTrue);
      expect(sshProbe['stdout'], contains('VIBEKITS_SIMULATOR_SSH_READY'));

      final Directory uploadRoot = await Directory.systemTemp.createTemp(
        'vibekits-real-simulator-',
      );
      addTearDown(() => uploadRoot.delete(recursive: true));
      final File uploadSource = File('${uploadRoot.path}/transport-proof.txt');
      await uploadSource.writeAsString('vibekits-id-only-sftp-proof\n');
      final Map<String, Object?> upload = await controller.uploadFile(
        routingId,
        uploadSource.path,
      );
      expect(upload['uploaded'], isTrue);
      expect('${upload['sha256']}', hasLength(64));
      final String remotePath = '${upload['remotePath']}';
      expect(remotePath, startsWith('/tmp/vibekits-simulator-$routingId/'));
      addTearDown(() async {
        try {
          await controller.runSshCommand(routingId, "rm -f '$remotePath'");
        } on Object {
          // closeAll remains the authoritative transport cleanup path.
        }
      });
      final String adbSerial =
          Platform.environment['VIBEKITS_REAL_REMOTE_ADB_SERIAL'] ?? '';
      var adbVerified = false;
      if (adbSerial.isNotEmpty) {
        final Map<String, Object?> adbList = _toolData(
          await controller.call(
            routingId,
            'vibekits.adb.list_devices',
            const <String, Object?>{},
          ),
        );
        final List<Object?> devices = List<Object?>.from(
          adbList['devices']! as List,
        );
        expect(
          devices.whereType<Map>().any(
            (Map<Object?, Object?> device) =>
                '${device['serial']}' == adbSerial &&
                '${device['state']}' == 'device',
          ),
          isTrue,
        );
        final Map<String, Object?> adbIdentity = _toolData(
          await controller.call(
            routingId,
            'vibekits.adb.shell',
            <String, Object?>{
              'serial': adbSerial,
              'arguments': const <String>['getprop', 'ro.product.model'],
            },
          ),
        );
        expect('${adbIdentity['stdout']}'.trim(), isNotEmpty);
        _toolData(
          await controller.call(
            routingId,
            'vibekits.adb.logcat',
            <String, Object?>{'serial': adbSerial, 'lines': 20},
          ),
        );

        final String androidPath =
            '/data/local/tmp/vibekits-simulator-$routingId-proof.txt';
        final String roundTripPath = '$remotePath.adb-roundtrip';
        addTearDown(() async {
          try {
            await controller.call(
              routingId,
              'vibekits.adb.shell',
              <String, Object?>{
                'serial': adbSerial,
                'arguments': <String>['rm', '-f', androidPath],
              },
            );
            await controller.runSshCommand(routingId, "rm -f '$roundTripPath'");
          } on Object {
            // The transport teardown still closes every managed tunnel.
          }
        });
        _toolData(
          await controller.call(
            routingId,
            'vibekits.adb.push_file',
            <String, Object?>{
              'serial': adbSerial,
              'localPath': remotePath,
              'remotePath': androidPath,
            },
          ),
        );
        final Map<String, Object?> adbPull = _toolData(
          await controller
              .call(routingId, 'vibekits.adb.pull_file', <String, Object?>{
                'serial': adbSerial,
                'remotePath': androidPath,
                'localPath': roundTripPath,
                'overwrite': true,
              }),
        );
        expect(adbPull['bytes'], upload['bytes']);

        final String apkPath =
            Platform.environment['VIBEKITS_REAL_REMOTE_APK_PATH'] ?? '';
        if (apkPath.isNotEmpty) {
          final Map<String, Object?> apkUpload = await controller.uploadFile(
            routingId,
            apkPath,
          );
          final String remoteApkPath = '${apkUpload['remotePath']}';
          addTearDown(() async {
            try {
              await controller.runSshCommand(
                routingId,
                "rm -f '$remoteApkPath'",
              );
            } on Object {
              // The target may already be offline during teardown.
            }
          });
          _toolData(
            await controller.call(
              routingId,
              'vibekits.adb.install_apk',
              <String, Object?>{
                'serial': adbSerial,
                'apkPath': remoteApkPath,
                'replace': true,
              },
            ),
          );
        }
        adbVerified = true;
      }
      Map<String, Object?> assistance = _toolData(
        await controller.call(
          routingId,
          'vibekits.remote_assistance.status',
          const <String, Object?>{},
        ),
      );
      if (enableAssistance && assistance['enabled'] != true) {
        _toolData(
          await controller.call(
            routingId,
            'vibekits.remote_assistance.set_enabled',
            const <String, Object?>{'enabled': true},
          ),
        );
        assistance = _toolData(
          await controller.call(
            routingId,
            'vibekits.remote_assistance.status',
            const <String, Object?>{},
          ),
        );
      }
      if (enableAssistance) expect(assistance['enabled'], isTrue);
      final String targetStopFile =
          Platform.environment['VIBEKITS_REAL_TARGET_STOP_FILE'] ?? '';
      if (targetStopFile.isNotEmpty) {
        final Map<String, Object?> stopped = await controller.runSshCommand(
          routingId,
          "printf PASS > '$targetStopFile'",
        );
        expect(stopped['ok'], isTrue);
      }
      // Never print remote process rows, paths, credentials or application
      // data. Counts and transport mode are sufficient acceptance evidence.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_SIMULATOR tools=${tools.length} '
        'forceRelay=$forceRelay responseKeys=${result.keys.length} '
        'sshReady=${sshProbe['ok'] == true} '
        'uploadBytes=${upload['bytes']} uploadShaVerified=true '
        'adbVerified=$adbVerified '
        'assistanceEnabled=${assistance['enabled'] == true}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_SIMULATOR=1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Map<String, Object?> _toolData(Map<String, Object?> result) {
  final Object? rawStructured = result['structuredContent'];
  expect(rawStructured, isA<Map>());
  final Map<String, Object?> structured = Map<String, Object?>.from(
    rawStructured! as Map,
  );
  if (structured['ok'] != true) {
    throw StateError(
      'remote tool rejected: ${structured['error'] ?? 'unknown error'}',
    );
  }
  expect(structured['data'], isA<Map>());
  return Map<String, Object?>.from(structured['data']! as Map);
}
