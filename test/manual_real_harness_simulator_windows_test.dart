import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_REMOTE_WINDOWS'] == '1';

  test(
    'remote Windows ID supports tools, SSH, SFTP, app control, logs and screenshot',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      expect(File(executable).existsSync(), isTrue);
      expect(routingId, isNotEmpty);

      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      final controller = HarnessSimulatorController(
        resolveHost: () async => host,
      );
      addTearDown(() async {
        await controller.closeAll();
        await RustDeskHarnessShareService.stopHost(
          configuredExecutable: executable,
        );
      });

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP connect');
      final connected = await controller.connect(routingId, forceRelay: true);
      expect(connected['connected'], isTrue);
      final tools = controller.catalog(routingId);
      expect(tools.length, greaterThan(200));
      for (final name in <String>[
        'vibekits.device.applications',
        'vibekits.device.app_install',
        'vibekits.device.app_uninstall',
        'vibekits.device.app_control',
        'vibekits.device.processes',
        'vibekits.device.logs',
        'vibekits.device.screenshot',
      ]) {
        expect(tools.any((tool) => tool['name'] == name), isTrue, reason: name);
      }

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP applications');
      final applications = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.applications',
          const <String, Object?>{'query': '', 'limit': 20},
        ),
      );
      expect(applications['platform'], 'windows');
      expect(applications['applications'], isA<List>());

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP ssh');
      final ssh = await controller.runSshCommand(
        routingId,
        r'cmd /d /c echo VIBEKITS_WINDOWS_SSH_READY',
      );
      expect(ssh['ok'], isTrue, reason: '$ssh');
      expect(ssh['stdout'], contains('VIBEKITS_WINDOWS_SSH_READY'));

      // OpenSSH's Windows default shell varies by host. EncodedCommand keeps
      // a PowerShell script intact across either cmd.exe or PowerShell SSH
      // shells, including Unicode content and shell metacharacters.
      const script = "Write-Output 'VIBEKITS_WINDOWS_SCRIPT_READY'";
      final scriptBytes = <int>[
        for (final unit in script.codeUnits) ...<int>[unit & 0xff, unit >> 8],
      ];
      final scriptResult = await controller.runSshCommand(
        routingId,
        'powershell.exe -NoLogo -NoProfile -NonInteractive '
        '-EncodedCommand ${base64Encode(scriptBytes)}',
      );
      expect(scriptResult['ok'], isTrue, reason: '$scriptResult');
      expect(scriptResult['stdout'], contains('VIBEKITS_WINDOWS_SCRIPT_READY'));

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP sftp');
      final temp = await Directory.systemTemp.createTemp(
        'vibekits-windows-real-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final fixture = File('${temp.path}/sftp-proof.txt');
      await fixture.writeAsString('VIBEKITS_WINDOWS_SFTP_READY\n', flush: true);
      final uploaded = await controller.uploadFile(routingId, fixture.path);
      expect(uploaded['uploaded'], isTrue);
      expect('${uploaded['sha256']}', hasLength(64));

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP launch');
      final launched = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.app_control',
          const <String, Object?>{
            'action': 'launch',
            'target': r'C:\Windows\System32\notepad.exe',
          },
        ),
      );
      expect(launched['platform'], 'windows');
      expect(launched['pid'], isA<int>());
      await Future<void>.delayed(const Duration(seconds: 1));

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP processes');
      final processes = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.processes',
          const <String, Object?>{'query': 'notepad.exe', 'limit': 20},
        ),
      );
      // ignore: avoid_print
      print('WINDOWS_REAL_PROCESSES $processes');
      expect(processes['processes'], isA<List>());
      expect((processes['processes'] as List), isNotEmpty);

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP stop');
      final stopped = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.app_control',
          const <String, Object?>{'action': 'stop', 'target': 'notepad.exe'},
        ),
      );
      expect(stopped['platform'], 'windows');

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP logs');
      final logs = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.logs',
          const <String, Object?>{
            'processName': 'Vibekits',
            'seconds': 300,
            'maxLines': 100,
          },
        ),
      );
      // ignore: avoid_print
      print('WINDOWS_REAL_LOGS $logs');
      expect(logs['source'], 'Windows Application Event Log');

      // ignore: avoid_print
      print('WINDOWS_REAL_STEP screenshot');
      final screenshot = await controller.captureScreenshot(routingId);
      expect(screenshot['captured'], isTrue);
      expect(screenshot['targetSha256'], screenshot['sha256']);
      expect(await File('${screenshot['localPath']}').exists(), isTrue);

      // ignore: avoid_print
      print(
        'HARNESS_REAL_WINDOWS tools=${tools.length} '
        'apps=${(applications['applications'] as List).length} '
        'ssh=true sftp=true appControl=true logs=true screenshot=true',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_WINDOWS=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Map<String, Object?> _toolData(Map<String, Object?> raw) {
  final structured = raw['structuredContent'];
  if (structured is! Map) return raw;
  final envelope = Map<String, Object?>.from(structured);
  final data = envelope['data'];
  return data is Map ? Map<String, Object?>.from(data) : envelope;
}
