import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:xml/xml.dart';

void main() {
  final enabled =
      Platform.environment['VIBEKITS_REAL_PAD_REMOTE_ASSISTANCE'] == '1';

  test(
    'PAD connects to a remembered or explicitly approved Harness peer by ID',
    () async {
      final serial =
          Platform.environment['VIBEKITS_REAL_S1_TARGET'] ??
          '192.168.3.75:5555';
      final remoteId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID']?.trim() ?? '';
      final adbPath =
          Platform.environment['VIBEKITS_REAL_S1_ADB']?.trim() ?? '';
      final apkPath =
          Platform.environment['VIBEKITS_REAL_S1_APK']?.trim() ?? '';
      final evidenceRoot = Directory(
        Platform.environment['VIBEKITS_REAL_S1_EVIDENCE'] ??
            '${Directory.systemTemp.path}/vibekits-pad-remote-assistance',
      );
      expect(RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(remoteId), isTrue);
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

      await invoke(VibekitsHarnessToolBridge.adbConnectId, <String, Object?>{
        'address': serial,
      });
      if (apkPath.isNotEmpty) {
        expect(File(apkPath).existsSync(), isTrue);
        await invoke(
          VibekitsHarnessToolBridge.adbInstallApkId,
          <String, Object?>{
            'serial': serial,
            'apkPath': apkPath,
            'replace': true,
          },
        );
      }
      // Start every real-device run from a clean controller process. This
      // closes a tunnel left by an interrupted prior run without clearing app
      // data, remembered peers, or user settings.
      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': serial,
        'arguments': const <String>[
          'shell',
          'am',
          'force-stop',
          'com.vibekits.vibekits',
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': serial,
        'arguments': const <String>[
          'shell',
          'monkey',
          '-p',
          'com.vibekits.vibekits',
          '-c',
          'android.intent.category.LAUNCHER',
          '1',
        ],
      });
      await Future<void>.delayed(const Duration(seconds: 2));

      var sequence = 0;
      Future<_UiState> readUi(String label) async {
        final remoteXml = '/sdcard/Download/vibekits-pad-ui.xml';
        await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
          'serial': serial,
          'arguments': <String>['shell', 'uiautomator', 'dump', remoteXml],
        });
        final localXml = File(
          '${evidenceRoot.path}/${sequence.toString().padLeft(2, '0')}-$label.xml',
        );
        await invoke(VibekitsHarnessToolBridge.adbPullFileId, <String, Object?>{
          'serial': serial,
          'remotePath': remoteXml,
          'localPath': localXml.path,
          'overwrite': true,
        });
        final screenshot = File(
          '${evidenceRoot.path}/${sequence.toString().padLeft(2, '0')}-$label.png',
        );
        await invoke(
          VibekitsHarnessToolBridge.adbScreenshotId,
          <String, Object?>{
            'serial': serial,
            'localPath': screenshot.path,
            'overwrite': true,
          },
        );
        sequence++;
        return _UiState(XmlDocument.parse(await localXml.readAsString()));
      }

      Future<void> tap(_Bounds bounds) =>
          invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
            'serial': serial,
            'arguments': <String>[
              'shell',
              'input',
              'tap',
              '${bounds.centerX}',
              '${bounds.centerY}',
            ],
          });

      var ui = await readUi('before');
      if (!ui.text.contains('连接远程设备')) {
        final settings =
            ui.node(text: '设置') ??
            ui.node(description: '设置') ??
            ui.node(descriptionContains: '设置');
        expect(settings, isNotNull, reason: 'PAD_SETTINGS_ENTRY_NOT_FOUND');
        await tap(settings!.bounds);
        await Future<void>.delayed(const Duration(seconds: 1));
        ui = await readUi('settings');
      }
      if (!ui.text.contains('连接远程设备')) {
        final advanced = ui.node(text: '高级') ?? ui.node(description: '高级');
        expect(advanced, isNotNull, reason: 'PAD_ADVANCED_TAB_NOT_FOUND');
        await tap(advanced!.bounds);
        await Future<void>.delayed(const Duration(seconds: 1));
        ui = await readUi('advanced');
      }
      expect(ui.text, contains('连接远程设备'));
      final input = ui.firstEditable;
      expect(input, isNotNull, reason: 'PAD_REMOTE_ID_FIELD_NOT_FOUND');
      await tap(input!.bounds);
      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': serial,
        'arguments': const <String>['shell', 'input', 'keyevent', '123'],
      });
      for (var index = 0; index < 24; index++) {
        await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
          'serial': serial,
          'arguments': const <String>['shell', 'input', 'keyevent', '67'],
        });
      }
      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': serial,
        'arguments': <String>['shell', 'input', 'text', remoteId],
      });
      await invoke(VibekitsHarnessToolBridge.adbCommandId, <String, Object?>{
        'serial': serial,
        'arguments': const <String>['shell', 'input', 'keyevent', '4'],
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      ui = await readUi('id-entered');
      expect(ui.text, contains(remoteId));
      final connect = ui.node(text: '协同') ?? ui.node(description: '协同');
      expect(connect, isNotNull, reason: 'PAD_REMOTE_CONNECT_BUTTON_NOT_FOUND');
      await tap(connect!.bounds);

      final deadline = DateTime.now().add(const Duration(minutes: 3));
      String lastText = '';
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        ui = await readUi('poll');
        lastText = ui.text;
        if (lastText.contains('协同已连接') || lastText.contains('远端项目状态已同步')) {
          // ignore: avoid_print
          print(
            'HARNESS_REAL_PAD_ASSISTANCE target=$serial peer=$remoteId '
            'state=connected evidence=${evidenceRoot.path}',
          );
          return;
        }
        if (lastText.contains('PAIRING_BAD_PASSWORD') ||
            lastText.contains('PAIRING_BAD_REQUEST') ||
            lastText.contains('PAIRING_REJECTED') ||
            lastText.contains('REMOTE_TUNNEL_TLS_TIMEOUT') ||
            lastText.contains('transport_failed')) {
          fail('PAD_REMOTE_ASSISTANCE_FAILED: $lastText');
        }
      }
      fail('PAD_REMOTE_ASSISTANCE_TIMEOUT: $lastText');
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_PAD_REMOTE_ASSISTANCE=1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class _UiState {
  _UiState(this.document);
  final XmlDocument document;

  Iterable<XmlElement> get nodes => document.findAllElements('node');

  String get text => nodes
      .expand(
        (node) => <String>[
          node.getAttribute('text') ?? '',
          node.getAttribute('content-desc') ?? '',
        ],
      )
      .where((value) => value.isNotEmpty)
      .join('\n');

  _UiNode? node({
    String? text,
    String? description,
    String? descriptionContains,
  }) {
    for (final node in nodes) {
      if ((text != null && node.getAttribute('text') == text) ||
          (description != null &&
              node.getAttribute('content-desc') == description) ||
          (descriptionContains != null &&
              (node.getAttribute('content-desc') ?? '').contains(
                descriptionContains,
              ))) {
        return _UiNode(node);
      }
    }
    return null;
  }

  _UiNode? get firstEditable {
    for (final node in nodes) {
      if ((node.getAttribute('class') ?? '').contains('EditText')) {
        return _UiNode(node);
      }
    }
    return null;
  }
}

final class _UiNode {
  _UiNode(XmlElement node)
    : bounds = _Bounds.parse(node.getAttribute('bounds') ?? '');
  final _Bounds bounds;
}

final class _Bounds {
  const _Bounds(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;

  static _Bounds parse(String value) {
    final match = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$').firstMatch(value);
    if (match == null) throw FormatException('Invalid UI bounds: $value');
    return _Bounds(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
  }
}
