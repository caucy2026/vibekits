import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_REMOTE_APP_PROBE'] == '1';

  test(
    'probes an installed app and preserves a current target screenshot',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final identity =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_IDENTITY'] ?? '';
      final appName =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_APP_NAME'] ?? '';
      expect(File(executable).existsSync(), isTrue);
      expect(routingId, isNotEmpty);
      expect(identity, isNotEmpty);
      expect(appName, isNotEmpty);

      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      final controller = HarnessSimulatorController(
        resolveHost: () async => host,
      );
      addTearDown(controller.closeAll);
      await controller.connect(
        routingId,
        forceRelay: Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1',
      );

      final apps = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.applications',
          <String, Object?>{'query': identity, 'limit': 20},
        ),
      );
      final applications = (apps['applications'] as List?) ?? const [];
      expect(applications, isNotEmpty, reason: 'target app is not installed');
      final assistance = _toolData(
        await controller.call(
          routingId,
          'vibekits.remote_assistance.status',
          const <String, Object?>{},
        ),
      );

      final launch = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.app_control',
          <String, Object?>{'action': 'launch', 'target': appName},
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      final processes = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.processes',
          const <String, Object?>{'query': 'KEMI', 'limit': 50},
        ),
      );
      final logs = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.logs',
          <String, Object?>{
            'processName': appName,
            'seconds': 300,
            'maxLines': 200,
          },
        ),
      );
      final crashes = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.crash_reports',
          const <String, Object?>{'appName': 'KEMI', 'limit': 5},
        ),
      );
      final screenshot = await controller.captureScreenshot(routingId);
      final screenshotFile = File('${screenshot['localPath']}');
      expect(await screenshotFile.exists(), isTrue);
      final signature = await controller.runSshCommand(
        routingId,
        "/usr/bin/codesign --verify --deep --strict '/Applications/KEMI远程办公.app'",
      );
      expect(signature['ok'], isTrue, reason: '$signature');
      final gatekeeper = await controller.runSshCommand(
        routingId,
        "/usr/sbin/spctl -a -t exec -vv '/Applications/KEMI远程办公.app'",
      );
      expect(gatekeeper['ok'], isTrue, reason: '$gatekeeper');
      final executableHash = await controller.runSshCommand(
        routingId,
        "/usr/bin/shasum -a 256 '/Applications/KEMI远程办公.app/Contents/MacOS/KEMI远程办公'",
      );
      expect(executableHash['ok'], isTrue, reason: '$executableHash');
      final expectedExecutableHash =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_EXECUTABLE_SHA256'] ??
          '';
      if (expectedExecutableHash.isNotEmpty) {
        expect(
          '${executableHash['stdout']}'.trim().toLowerCase(),
          startsWith(expectedExecutableHash.toLowerCase()),
        );
      }
      final market = await controller.runSshCommand(
        routingId,
        "/usr/bin/curl --fail --silent --show-error --max-time 15 'https://kemi.newlinksz.com/kd-api/api/store/apps?page=1&pageSize=100&os=macos'",
      );
      expect(market['ok'], isTrue, reason: '$market');
      final marketEnvelope = jsonDecode('${market['stdout']}');
      expect(marketEnvelope, isA<Map>());
      expect((marketEnvelope as Map)['status'], 200);
      expect(((marketEnvelope['data'] as Map)['list'] as List), isNotEmpty);

      final app = applications.whereType<Map>().first;
      final processList = (processes['processes'] as List?) ?? const [];
      final logLines = (logs['lines'] as List?) ?? const [];
      final reports = (crashes['reports'] as List?) ?? const [];
      // Do not print screen or log contents. Counts, identity and the retained
      // local screenshot are sufficient to guide the next diagnostic action.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_APP_PROBE identity=${app['bundleId']} '
        'version=${app['version']} build=${app['build']} '
        'launchOk=${launch['ok']} processes=${processList.length} '
        'logLines=${logLines.length} crashReports=${reports.length} '
        'signature=true gatekeeper=true '
        'executableHash=true marketApps=true '
        'assistanceEnabled=${assistance['enabled']} '
        'assistancePhase=${assistance['phase']} '
        'screenshot=${screenshotFile.path} sha=${screenshot['sha256']}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_APP_PROBE=1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Map<String, Object?> _toolData(Map<String, Object?> raw) {
  final structured = raw['structuredContent'];
  if (structured is! Map) return raw;
  final envelope = Map<String, Object?>.from(structured);
  final data = envelope['data'];
  return data is Map ? Map<String, Object?>.from(data) : envelope;
}
