import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vibekits/features/dev_tools/domain/native_app_debug_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_access_settings.dart';

// macOS ZIP 安装回归：`unzip -Z1` 的列表名与 `ditto -x -k` 的落盘名不一致。
//
// 在 macOS 12.6.4（Info-ZIP unzip 6.0）上对同一个归档实测：
//   /usr/bin/unzip -Z1   → KEMI e8 bf 3f e7 a8 3f e5 3f 3f e5 3f ac .app
//   /usr/bin/ditto -x -k → KEMI e8 bf 9c e7 a8 8b e5 8a 9e e5 85 ac .app
// 非 ASCII 字节被 unzip 按本地字符集转写成 '?'，二者指向同一个 App。因此列表名
// 只能用于结构校验，绝不能当作磁盘路径；下面用假 runner 精确复刻这一差异，而
// 解压/复制仍走真实 ditto，保证断言的是真实落盘结果。
const String kMacZipRealBundle = 'KEMI远程办公.app';
const String kMacZipMangledBundle = 'KEMI???.app';
const String kMacZipBundleId = 'com.example.kemi.zh.regression';
const String kMacZipListing =
    '$kMacZipMangledBundle/\n'
    '$kMacZipMangledBundle/Contents/\n'
    '$kMacZipMangledBundle/Contents/Info.plist\n';

typedef _MacZipRunner = ({
  NativeDebugProcessRunner run,
  List<String> calls,
  List<String> events,
});

_MacZipRunner _macZipRunner({
  String listing = kMacZipListing,
  String bundleId = kMacZipBundleId,
  bool extractBundle = true,
  bool gatekeeperAccepted = true,
  bool installedSignatureValid = true,
}) {
  final calls = <String>[];
  final events = <String>[];
  var codeSignCalls = 0;
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add('$executable ${arguments.join(' ')}');
    switch (executable) {
      case '/usr/bin/unzip':
        return ProcessResult(1, 0, listing, '');
      case '/usr/bin/ditto':
        final extracting =
            arguments.length >= 4 &&
            arguments[0] == '-x' &&
            arguments[1] == '-k';
        if (extracting) {
          events.add('extract');
          if (!extractBundle) return ProcessResult(1, 0, '', '');
          final contents = Directory(
            '${arguments[3]}/$kMacZipRealBundle/Contents',
          );
          await contents.create(recursive: true);
          await File('${contents.path}/Info.plist').writeAsString('{}');
          return ProcessResult(1, 0, '', '');
        }
        // 复制阶段交给真实 ditto，确保断言的是真实落盘内容。
        return Process.run('/usr/bin/ditto', arguments);
      case '/usr/bin/plutil':
        if (arguments.last.contains('-extract/$kMacZipRealBundle/')) {
          return ProcessResult(
            1,
            0,
            jsonEncode(<String, Object?>{
              'CFBundleIdentifier': bundleId,
              'CFBundleName': 'KEMI远程办公',
              'CFBundleShortVersionString': '1.4.126',
              'CFBundleVersion': '263',
            }),
            '',
          );
        }
        return ProcessResult(1, 1, '', 'not a bundle under test');
      case '/usr/bin/codesign':
        codeSignCalls += 1;
        if (arguments.last.contains(kMacZipRealBundle)) {
          events.add('codesign:$codeSignCalls');
        }
        final ok = codeSignCalls == 1 || installedSignatureValid;
        return ProcessResult(1, ok ? 0 : 1, '', ok ? '' : 'invalid signature');
      case '/usr/sbin/spctl':
        return ProcessResult(
          1,
          gatekeeperAccepted ? 0 : 1,
          gatekeeperAccepted ? 'accepted' : 'rejected',
          '',
        );
      case '/usr/libexec/PlistBuddy':
        return ProcessResult(1, 1, '', 'not a bundle under test');
    }
    return ProcessResult(1, 1, '', 'unexpected executable: $executable');
  }

  return (run: run, calls: calls, events: events);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => HarnessSimulatorAccessSettings.setEnabled(true));
  tearDown(() => HarnessSimulatorAccessSettings.setEnabled(false));

  test('macOS 中文 App ZIP 可自动安装并忽略 AppleDouble 元数据', () async {
    if (!Platform.isMacOS) return;
    final root = await Directory.systemTemp.createTemp('kemi-zip-regression-');
    addTearDown(() => root.delete(recursive: true));
    final package = File('${root.path}/candidate.zip');
    await package.writeAsBytes(<int>[1, 2, 3]);
    final checksum = sha256.convert(await package.readAsBytes()).toString();
    final runner = _macZipRunner(
      listing:
          '$kMacZipListing'
          '__MACOSX/\n'
          '__MACOSX/$kMacZipMangledBundle/Contents/._Info.plist\n',
    );

    final result = await NativeAppDebugService.installApplication(
      packagePath: package.path,
      expectedSha256: checksum,
      expectedIdentity: kMacZipBundleId,
      runner: runner.run,
      stagingRoot: Directory('${root.path}/staging'),
      destinationRoot: Directory('${root.path}/installed'),
    );

    expect(result['ok'], isTrue);
    expect(
      result['installedPath'],
      '${root.path}/installed/$kMacZipRealBundle',
    );
    expect(result['version'], '1.4.126');
    expect(
      await File('${result['installedPath']}/Contents/Info.plist').exists(),
      isTrue,
    );
    expect(
      runner.events,
      containsAllInOrder(<String>['extract', 'codesign:1']),
    );
  });

  test('macOS ZIP 的额外应用载荷仍被拒绝', () async {
    if (!Platform.isMacOS) return;
    final root = await Directory.systemTemp.createTemp('kemi-zip-extra-');
    addTearDown(() => root.delete(recursive: true));
    final package = File('${root.path}/candidate.zip');
    await package.writeAsBytes(<int>[1, 2, 3]);
    final checksum = sha256.convert(await package.readAsBytes()).toString();
    final runner = _macZipRunner(
      listing:
          '$kMacZipListing'
          '__MACOSX/$kMacZipMangledBundle/._Info.plist\n'
          'Another.app/Contents/Info.plist\n',
    );
    expect(
      () => NativeAppDebugService.installApplication(
        packagePath: package.path,
        expectedSha256: checksum,
        expectedIdentity: kMacZipBundleId,
        runner: runner.run,
        stagingRoot: Directory('${root.path}/staging'),
        destinationRoot: Directory('${root.path}/installed'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(runner.events, isEmpty);
  });

  test('macOS 进程工具可按其他 App 名筛选并返回真实字段', () async {
    if (!Platform.isMacOS) return;
    final result = await NativeAppDebugService.inspectProcesses(
      query: 'TargetApp',
      runner: (executable, arguments) async {
        expect(executable, '/bin/ps');
        expect(arguments, contains('pid=,ppid=,%cpu=,%mem=,etime=,command='));
        return ProcessResult(
          1,
          0,
          '  101 1 12.5 3.4 00:42 /Applications/TargetApp.app/Contents/MacOS/TargetApp\n'
              '  202 1  0.1 0.2 01:01 /Applications/Other.app/Contents/MacOS/Other\n',
          '',
        );
      },
    );
    final rows = result['processes']! as List<Object?>;
    expect(rows, hasLength(1));
    expect((rows.single as Map<String, Object?>)['pid'], 101);
    expect((rows.single as Map<String, Object?>)['cpuPercent'], 12.5);
  });

  test('macOS 日志工具固定调用 Unified Log 且参数不经过 shell', () async {
    if (!Platform.isMacOS) return;
    final result = await NativeAppDebugService.readLogs(
      processName: 'TargetApp',
      seconds: 60,
      maxLines: 2,
      runner: (executable, arguments) async {
        expect(executable, '/usr/bin/log');
        expect(arguments, containsAll(<String>['show', '--last', '60s']));
        expect(arguments.join(' '), contains('TargetApp'));
        return ProcessResult(1, 0, 'line1\nline2\nline3', '');
      },
    );
    expect(result['lines'], <String>['line2', 'line3']);
    expect(result['truncated'], isTrue);
    expect(result['source'], 'macOS Unified Log');
  });

  test('macOS 应用清单跳过单个损坏 App 并继续返回健康应用', () async {
    if (!Platform.isMacOS) return;
    var calls = 0;
    final result = await NativeAppDebugService.listApplications(
      query: 'com.example.healthy',
      limit: 1,
      runner: (executable, arguments) async {
        expect(executable, '/usr/bin/plutil');
        calls += 1;
        if (calls == 1) return ProcessResult(1, 0, '{}', 'invalid plist');
        return ProcessResult(
          2,
          0,
          '{"CFBundleIdentifier":"com.example.healthy",'
              '"CFBundleName":"Healthy App",'
              '"CFBundleShortVersionString":"1.0",'
              '"CFBundleVersion":"1"}',
          '',
        );
      },
    );
    expect(calls, greaterThanOrEqualTo(2));
    expect(result['applications'], hasLength(1));
  });

  test('应用控制拒绝换行注入和未知动作', () async {
    expect(
      () => NativeAppDebugService.controlApplication(
        action: 'launch',
        target: 'App\nmalicious',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => NativeAppDebugService.controlApplication(
        action: 'delete',
        target: 'TargetApp',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('控件操作拒绝模糊目标、空选择器和窗口外不受控参数', () async {
    if (!Platform.isMacOS) return;
    expect(
      () => NativeAppDebugService.inspectApplicationUi(),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => NativeAppDebugService.performApplicationUiAction(
        bundleId: 'com.example.target',
        action: 'press',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => NativeAppDebugService.performApplicationUiAction(
        bundleId: 'com.example.target',
        action: 'click',
        x: 10,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('控件树与语义点击通过 VibeKits 原生通道而非脚本', () async {
    if (!Platform.isMacOS) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('vibekits/device_debug');
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'inspectApplicationUI') {
        expect(call.arguments, containsPair('bundleId', 'com.example.target'));
        return <String, Object?>{
          'ok': true,
          'authorized': true,
          'nodes': <Object?>[],
        };
      }
      if (call.method == 'performApplicationUIAction') {
        expect(call.arguments, containsPair('title', '关于'));
        return <String, Object?>{'ok': true, 'action': 'press'};
      }
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final inspected = await NativeAppDebugService.inspectApplicationUi(
      bundleId: 'com.example.target',
    );
    final pressed = await NativeAppDebugService.performApplicationUiAction(
      bundleId: 'com.example.target',
      action: 'press',
      title: '关于',
    );
    expect(inspected['authorized'], isTrue);
    expect(pressed['ok'], isTrue);
    expect(methods, <String>[
      'inspectApplicationUI',
      'performApplicationUIAction',
    ]);
  });
}
