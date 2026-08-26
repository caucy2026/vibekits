import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/sftp_service.dart';
import 'package:vibekits/features/dev_tools/presentation/sftp_browser.dart';

void main() {
  testWidgets('SFTP 双栏列出文件并完成上传下载', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory local = Directory.systemTemp.createTempSync('vibe_sftp_');
    addTearDown(() => local.deleteSync(recursive: true));
    File('${local.path}${Platform.pathSeparator}upload.bin')
        .writeAsBytesSync(<int>[1, 2, 3]);
    final _FakeRemoteFileClient client = _FakeRemoteFileClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SftpBrowser(
            client: client,
            initialLocalPath: local.path,
            initialRemotePath: '/',
            scanLocalDirectory: _testLocalScanner,
          ),
        ),
      ),
    );
    await _pumpAsync(tester);
    expect(find.text('upload.bin'), findsOneWidget);
    expect(find.text('download.bin'), findsOneWidget);

    await tester.tap(find.text('upload.bin'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sftp-upload-selected')));
    await _pumpAsync(tester);
    expect(client.uploaded, <String>['/upload.bin']);
    expect(find.textContaining('完成'), findsOneWidget);

    await tester.tap(find.text('download.bin'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sftp-download-selected')));
    await _pumpAsync(tester);
    expect(client.downloaded, hasLength(1));
    expect(
      File('${local.path}${Platform.pathSeparator}download.bin')
          .readAsBytesSync(),
      <int>[4, 5, 6],
    );
  });

  testWidgets('同名冲突提供四个动作且默认焦点不是覆盖', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory local = Directory.systemTemp.createTempSync('vibe_sftp_');
    addTearDown(() => local.deleteSync(recursive: true));
    File('${local.path}${Platform.pathSeparator}download.bin')
        .writeAsBytesSync(<int>[0]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SftpBrowser(
            client: _FakeRemoteFileClient(),
            initialLocalPath: local.path,
            initialRemotePath: '/',
            scanLocalDirectory: _testLocalScanner,
          ),
        ),
      ),
    );
    await _pumpAsync(tester);
    await tester.tap(find.text('download.bin').last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('sftp-download-selected')));
    await _pumpAsync(tester);

    expect(find.text('覆盖'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '跳过'))
          .autofocus,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('sftp-conflict-overwrite')),
          )
          .autofocus,
      isFalse,
    );
  });

  testWidgets('进行中的 SFTP 传输可取消并进入已取消状态', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory local = Directory.systemTemp.createTempSync('vibe_sftp_');
    addTearDown(() => local.deleteSync(recursive: true));
    File('${local.path}${Platform.pathSeparator}upload.bin')
        .writeAsBytesSync(List<int>.filled(64, 7));
    final _FakeRemoteFileClient client = _FakeRemoteFileClient(
      blockUpload: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SftpBrowser(
            client: client,
            initialLocalPath: local.path,
            initialRemotePath: '/',
            scanLocalDirectory: _testLocalScanner,
          ),
        ),
      ),
    );
    await _pumpAsync(tester);
    await tester.tap(find.text('upload.bin'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sftp-upload-selected')));
    await tester.pump();
    expect(find.byKey(const Key('sftp-cancel-transfer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sftp-cancel-transfer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('已取消'), findsOneWidget);
  });

  testWidgets('SFTP 本地和远端可独立后退与返回上级', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory local = Directory.systemTemp.createTempSync('vibe_nav_');
    addTearDown(() => local.deleteSync(recursive: true));
    final Directory child = Directory(
      '${local.path}${Platform.pathSeparator}local-child',
    )..createSync();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SftpBrowser(
            client: _NavigationRemoteFileClient(),
            initialLocalPath: local.path,
            initialRemotePath: '/',
            scanLocalDirectory: _testLocalScanner,
          ),
        ),
      ),
    );
    await _pumpAsync(tester);

    await tester.tap(find.text('local-child'));
    await _pumpAsync(tester);
    expect(find.text(child.absolute.path), findsOneWidget);
    await tester.tap(find.byKey(const Key('sftp-local-back')));
    await _pumpAsync(tester);
    expect(find.text(local.absolute.path), findsOneWidget);
    await tester.tap(find.text('local-child'));
    await _pumpAsync(tester);
    await tester.tap(find.byKey(const Key('sftp-local-up')));
    await _pumpAsync(tester);
    expect(find.text(local.absolute.path), findsOneWidget);

    await tester.tap(find.text('remote-child'));
    await _pumpAsync(tester);
    expect(find.text('/remote-child'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sftp-remote-back')));
    await _pumpAsync(tester);
    expect(find.text('/'), findsOneWidget);
    await tester.tap(find.text('remote-child'));
    await _pumpAsync(tester);
    await tester.tap(find.byKey(const Key('sftp-remote-up')));
    await _pumpAsync(tester);
    expect(find.text('/'), findsOneWidget);
  });
}

Future<void> _pumpAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<({String path, List<(String, String, bool, int)> entries})>
_testLocalScanner(String path) async {
  final List<(String, String, bool, int)> entries = Directory(path)
      .listSync(followLinks: false)
      .map((FileSystemEntity entity) {
        final FileStat stat = entity.statSync();
        return (
          entity.uri.pathSegments
              .where((String value) => value.isNotEmpty)
              .last,
          entity.path,
          stat.type == FileSystemEntityType.directory,
          stat.size,
        );
      })
      .toList(growable: false);
  return (path: Directory(path).absolute.path, entries: entries);
}

class _FakeRemoteFileClient implements RemoteFileClient {
  _FakeRemoteFileClient({this.blockUpload = false});

  final bool blockUpload;
  final List<String> uploaded = <String>[];
  final List<String> downloaded = <String>[];
  final List<RemoteFileEntry> entries = <RemoteFileEntry>[
    const RemoteFileEntry(
      name: 'download.bin',
      path: '/download.bin',
      isDirectory: false,
      size: 3,
    ),
  ];

  @override
  Future<String> absolute(String path) async => '/';

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async =>
      List<RemoteFileEntry>.of(entries);

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    final int total = File(localPath).lengthSync();
    onProgress(1, total);
    if (blockUpload) {
      await cancellation.whenCancelled;
      throw const SftpTransferCancelled();
    }
    uploaded.add(remotePath);
    entries.add(
      RemoteFileEntry(
        name: remotePath.split('/').last,
        path: remotePath,
        isDirectory: false,
        size: total,
      ),
    );
    onProgress(total, total);
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {
    downloaded.add(localPath);
    File(localPath).writeAsBytesSync(<int>[4, 5, 6]);
    onProgress(3, total);
  }

  @override
  Future<void> close() async {}
}

class _NavigationRemoteFileClient implements RemoteFileClient {
  @override
  Future<String> absolute(String path) async {
    if (path == '.' || path.isEmpty) return '/';
    return path;
  }

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async => path == '/'
      ? const <RemoteFileEntry>[
          RemoteFileEntry(
            name: 'remote-child',
            path: '/remote-child',
            isDirectory: true,
            size: 0,
          ),
        ]
      : const <RemoteFileEntry>[];

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {}

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    required int total,
    required bool overwrite,
    required SftpCancellationToken cancellation,
    required void Function(int bytes, int total) onProgress,
  }) async {}

  @override
  Future<void> close() async {}
}
