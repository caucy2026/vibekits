import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/port_forward_service.dart';
import 'package:vibekits/features/dev_tools/domain/remote_desktop_service.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';
import 'package:vibekits/features/dev_tools/domain/sftp_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';
import 'package:vibekits/features/dev_tools/presentation/remote_workspace.dart';

void main() {
  testWidgets('开发工具收到 Harness 意图后立即定位并更新 SSH 目标', (WidgetTester tester) async {
    Widget app(RemoteWorkspaceIntent intent, int serial) => MaterialApp(
      home: Scaffold(
        body: DevToolsTab(
          remoteWorkspaceIntent: intent,
          remoteWorkspaceIntentSerial: serial,
        ),
      ),
    );

    await tester.pumpWidget(
      app(const RemoteWorkspaceIntent(host: '192.168.3.20', user: 'root'), 1),
    );
    expect(find.byKey(const Key('remote-host')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('remote-host')))
          .controller
          ?.text,
      '192.168.3.20',
    );

    await tester.pumpWidget(
      app(
        const RemoteWorkspaceIntent(host: 'server.example.com', user: 'dev'),
        2,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('remote-host')))
          .controller
          ?.text,
      'server.example.com',
    );
  });

  testWidgets('SSH 工作区用一个主操作连接并发送输入', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeRemoteSession fake = _FakeRemoteSession();
    RemoteLaunchRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            remoteStartSession: (RemoteLaunchRequest request) async {
              captured = request;
              fake.addOutput('welcome from server');
              return fake;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'server.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'developer');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();

    expect(captured?.mode, RemoteSessionMode.ssh);
    expect(captured?.profile.host, 'server.example.com');
    expect(find.textContaining('welcome from server'), findsOneWidget);
    expect(find.text('断开'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('remote-command')), 'uname -a');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(fake.sentLines, <String>['uname -a']);

    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    expect(fake.running, isFalse);
  });

  testWidgets('非法主机在启动进程前给出明确错误', (WidgetTester tester) async {
    bool started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            remoteStartSession: (RemoteLaunchRequest request) async {
              started = true;
              return _FakeRemoteSession();
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('remote-host')), '-oBad');
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(started, isFalse);
    expect(find.byKey(const Key('remote-error')), findsOneWidget);
  });

  testWidgets('保存会话时普通设置不含密码且密码只写系统凭据', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String> persisted = <String>[];
    final Map<String, String> credentials = <String, String>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            remoteProfileIdGenerator: () => 'remote_test_1',
            onRemoteSessionProfilesChanged: (List<String> profiles) async {
              persisted = profiles;
            },
            remoteCredentialRead: (String key) async => credentials[key],
            remoteCredentialWrite: (String key, String value) async {
              credentials[key] = value;
            },
            remoteCredentialDelete: (String key) async {
              credentials.remove(key);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'server.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'developer');
    await tester.tap(find.byKey(const Key('remote-profile-save')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remote-profile-name')),
      '生产服务器',
    );
    await tester.enterText(
      find.byKey(const Key('remote-profile-secret')),
      'VK_SECRET_20260817_7f3a',
    );
    await tester.tap(find.byKey(const Key('remote-profile-confirm-save')));
    await tester.pumpAndSettle();

    expect(persisted, hasLength(1));
    expect(persisted.single, isNot(contains('VK_SECRET_20260817_7f3a')));
    expect(
      credentials['vibekits.remote-session.remote_test_1'],
      'VK_SECRET_20260817_7f3a',
    );
    expect(find.text('系统凭据已保存'), findsOneWidget);
  });

  testWidgets('最近会话可重启选择、编辑且不重复新增', (WidgetTester tester) async {
    const String initial =
        '{"version":1,"id":"remote_test_1","name":"生产服务器",'
        '"mode":"ssh","host":"old.example.com","user":"developer",'
        '"port":22,"identityFile":null,"favorite":false,'
        '"lastUsedEpochMs":0}';
    List<String> persisted = <String>[initial];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            initialRemoteSessionProfiles: persisted,
            onRemoteSessionProfilesChanged: (List<String> profiles) async {
              persisted = profiles;
            },
            remoteCredentialRead: (String key) async => 'saved',
            remoteCredentialWrite: (String key, String value) async {},
            remoteCredentialDelete: (String key) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生产服务器').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('remote-host')))
          .controller!
          .text,
      'old.example.com',
    );
    expect(find.text('系统凭据已保存'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'new.example.com',
    );
    await tester.tap(find.byKey(const Key('remote-profile-save')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('remote-profile-name')), '新名称');
    await tester.tap(find.byKey(const Key('remote-profile-confirm-save')));
    await tester.pumpAndSettle();

    expect(persisted, hasLength(1));
    expect(persisted.single, contains('new.example.com'));
    expect(persisted.single, contains('新名称'));
  });

  testWidgets('删除会话同时删除系统凭据且不影响其他记录', (WidgetTester tester) async {
    const String target =
        '{"version":1,"id":"target","name":"目标",'
        '"mode":"ssh","host":"target.example.com","user":"dev",'
        '"port":22,"favorite":false,"lastUsedEpochMs":0}';
    const String keep =
        '{"version":1,"id":"keep","name":"保留",'
        '"mode":"sftp","host":"keep.example.com","user":"dev",'
        '"port":22,"favorite":false,"lastUsedEpochMs":0}';
    List<String> persisted = <String>[target, keep];
    final List<String> deletedKeys = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            initialRemoteSessionProfiles: persisted,
            onRemoteSessionProfilesChanged: (List<String> profiles) async {
              persisted = profiles;
            },
            remoteCredentialRead: (String key) async => null,
            remoteCredentialWrite: (String key, String value) async {},
            remoteCredentialDelete: (String key) async {
              deletedKeys.add(key);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('目标').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote-profile-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote-profile-confirm-delete')));
    await tester.pumpAndSettle();

    expect(deletedKeys, <String>['vibekits.remote-session.target']);
    expect(persisted, hasLength(1));
    expect(persisted.single, contains('"id":"keep"'));
  });

  testWidgets('安全连接使用系统凭据并在确认后绑定主机指纹', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const String initial =
        '{"version":1,"id":"secure","name":"安全服务器",'
        '"mode":"ssh","host":"secure.example.com","user":"dev",'
        '"port":22,"favorite":true,"lastUsedEpochMs":0}';
    List<String> persisted = <String>[initial];
    String? receivedSecret;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            initialProfiles: persisted,
            onProfilesChanged: (List<String> profiles) async {
              persisted = profiles;
            },
            readCredential: (String key) async => 'system-vault-secret',
            writeCredential: (String key, String secret) async {},
            deleteCredential: (String key) async {},
            secureStartSession:
                (
                  RemoteLaunchRequest request,
                  String? secret,
                  RemoteHostKeyVerifier verifyHostKey,
                ) async {
                  receivedSecret = secret;
                  final bool trusted = await verifyHostKey(
                    'ssh-ed25519',
                    'SHA256:TrustedHostKey0123456789+/',
                  );
                  if (!trusted) throw StateError('主机指纹未确认');
                  return _FakeInteractiveRemoteSession();
                },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('★ 安全服务器').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();

    expect(receivedSecret, 'system-vault-secret');
    expect(find.text('确认主机指纹'), findsOneWidget);
    expect(
      find.textContaining('SHA256:TrustedHostKey0123456789+/'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remote-host-fingerprint-confirm')));
    await tester.pumpAndSettle();

    expect(persisted.single, contains('SHA256:TrustedHostKey0123456789+/'));
    expect(
      find.byKey(const Key('remote-interactive-terminal')),
      findsOneWidget,
    );
  });

  testWidgets('两个终端标签切换时输出互不串线且保留', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            startSession: (RemoteLaunchRequest request) async {
              starts += 1;
              final _FakeRemoteSession session = _FakeRemoteSession();
              session.addOutput(
                starts == 1 ? 'OUTPUT_ONLY_A' : 'OUTPUT_ONLY_B',
              );
              return session;
            },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'a.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('OUTPUT_ONLY_A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote-new-terminal')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'b.example.com',
    );
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('OUTPUT_ONLY_B'), findsOneWidget);
    expect(find.textContaining('OUTPUT_ONLY_A'), findsNothing);

    await tester.tap(find.text('dev@a.example.com'));
    await tester.pump();
    expect(find.textContaining('OUTPUT_ONLY_A'), findsOneWidget);
    expect(find.textContaining('OUTPUT_ONLY_B'), findsNothing);
    await tester.tap(find.text('dev@b.example.com'));
    await tester.pump();
    expect(find.textContaining('OUTPUT_ONLY_B'), findsOneWidget);
    expect(find.textContaining('OUTPUT_ONLY_A'), findsNothing);
  });

  testWidgets('终端搜索计数且多行粘贴确认前不发送', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeInteractiveRemoteSession session =
        _FakeInteractiveRemoteSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            startSession: (RemoteLaunchRequest request) async => session,
            readClipboard: () async => 'printf A\nprintf B',
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'a.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    session.addOutput('before needle-7f3a after\r\n');
    await tester.pump();

    await tester.tap(find.byKey(const Key('remote-terminal-search-toggle')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-terminal-search')),
      'needle-7f3a',
    );
    await tester.pump();
    expect(find.text('1 个匹配'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote-terminal-paste')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('remote-paste-preview')), findsOneWidget);
    expect(session.sentData, isEmpty);
    await tester.tap(find.byKey(const Key('remote-paste-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.sentData.join(), contains('printf A'));
    expect(session.sentData.join(), contains('printf B'));

    await tester.tap(find.byKey(const Key('remote-terminal-clear')));
    await tester.pump();
    expect(find.text('0 个匹配'), findsOneWidget);
  });

  testWidgets('SSH 登录后绿色按钮复用当前会话直接打开 SFTP', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeInteractiveRemoteSession session =
        _FakeInteractiveRemoteSession();
    final _FakeRemoteFileClient files = _FakeRemoteFileClient();
    RemoteSessionHandle? reusedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            startSession: (RemoteLaunchRequest request) async => session,
            connectAuthenticatedRemoteFiles:
                (RemoteSessionHandle activeSession) async {
                  reusedSession = activeSession;
                  return files;
                },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'files.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-open-session-sftp')), findsOneWidget);
    expect(find.text('SFTP 文件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remote-open-session-sftp')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(reusedSession, same(session));
    expect(session.running, isTrue);
    expect(find.byKey(const Key('sftp-browser')), findsOneWidget);
    expect(find.byKey(const Key('remote-session-secret')), findsNothing);

    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(files.closed, isTrue);
    expect(session.running, isTrue);
    expect(
      find.byKey(const Key('remote-interactive-terminal')),
      findsOneWidget,
    );
  });

  testWidgets('Harness 打开 SSH 后只输入一次密码并自动显示 SFTP', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeInteractiveRemoteSession session =
        _FakeInteractiveRemoteSession();
    final _FakeRemoteFileClient files = _FakeRemoteFileClient();
    String? receivedSecret;
    RemoteSessionHandle? reusedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            launchIntent: const RemoteWorkspaceIntent(
              host: '192.168.3.20',
              user: 'root',
              openSftpAfterConnect: true,
            ),
            launchIntentSerial: 1,
            secureStartSession:
                (
                  RemoteLaunchRequest request,
                  String? secret,
                  RemoteHostKeyVerifier verifyHostKey,
                ) async {
                  receivedSecret = secret;
                  return session;
                },
            connectAuthenticatedRemoteFiles:
                (RemoteSessionHandle activeSession) async {
                  reusedSession = activeSession;
                  return files;
                },
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('remote-host')))
          .controller
          ?.text,
      '192.168.3.20',
    );
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote-session-secret')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('remote-session-secret')),
      'only-once',
    );
    await tester.tap(find.byKey(const Key('remote-session-secret-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(receivedSecret, 'only-once');
    expect(reusedSession, same(session));
    expect(find.byKey(const Key('sftp-browser')), findsOneWidget);
    expect(find.byKey(const Key('remote-session-secret')), findsNothing);
  });

  testWidgets('连接中可立即取消且迟到会话自动释放', (WidgetTester tester) async {
    final Completer<RemoteSessionHandle> pending =
        Completer<RemoteSessionHandle>();
    final _FakeRemoteSession lateSession = _FakeRemoteSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            startSession: (RemoteLaunchRequest request) => pending.future,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'slow.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(find.text('取消连接'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(find.textContaining('连接已取消'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('remote-host'))).enabled,
      isNot(false),
    );

    pending.complete(lateSession);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(lateSession.running, isFalse);
    expect(find.byKey(const Key('remote-terminal-tabs')), findsNothing);
  });

  testWidgets('端口转发表支持本地、远程和 SOCKS5 并可逐条停止', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakePortForwardConnection connection = _FakePortForwardConnection();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            connectPortForwards: (
              RemoteConnectionProfile profile,
              String? secret,
              RemoteHostKeyVerifier verifier,
            ) async => connection,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'jump.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.text('端口转发'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-session-secret')),
      'test-secret',
    );
    await tester.tap(find.byKey(const Key('remote-session-secret-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(connection.specs.single.kind, PortForwardKind.local);
    expect(find.textContaining('127.0.0.1:8080'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('添加转发'), findsOneWidget);

    connection.failPort = 18082;
    await tester.enterText(find.byKey(const Key('remote-local-port')), '18082');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(find.textContaining('本地端口 18082 已占用'), findsOneWidget);
    expect(connection.handles, hasLength(1));
    connection.failPort = null;

    await tester.tap(find.text('远程'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('remote-local-port')), '18081');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(connection.specs.last.kind, PortForwardKind.remote);

    await tester.tap(find.text('SOCKS5'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('remote-local-port')), '1080');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(connection.specs.last.kind, PortForwardKind.dynamic);
    expect(find.textContaining('SOCKS5 127.0.0.1:1080'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote-forward-stop-0')));
    await tester.pump();
    expect(connection.handles.first.running, isFalse);
    expect(find.text('已停止'), findsOneWidget);
    expect(connection.connected, isTrue);

    await tester.tap(find.byKey(const Key('remote-forward-disconnect-all')));
    await tester.pump();
    expect(connection.connected, isFalse);
    expect(
      connection.handles.every((_FakePortForwardHandle item) => !item.running),
      isTrue,
    );
  });

  testWidgets('桌面模式保存脱敏记录并一次交给系统客户端', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String> persisted = <String>[];
    RemoteDesktopTarget? launched;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWorkspace(
            profileIdGenerator: () => 'desktop_test',
            onProfilesChanged: (List<String> profiles) async {
              persisted = profiles;
            },
            launchRemoteDesktop: (RemoteDesktopTarget target) async {
              launched = target;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('桌面'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('remote-host')), 'rdp.test');
    await tester.enterText(find.byKey(const Key('remote-port')), '3390');
    expect(find.byKey(const Key('remote-user')), findsNothing);
    expect(find.byKey(const Key('remote-identity')), findsNothing);

    await tester.tap(find.byKey(const Key('remote-profile-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote-profile-secret')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('remote-profile-name')),
      '测试桌面',
    );
    await tester.tap(find.byKey(const Key('remote-profile-confirm-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(persisted.single, contains('"mode":"remoteDesktop"'));
    expect(persisted.single, contains('"user":""'));

    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(launched?.host, 'rdp.test');
    expect(launched?.port, 3390);
    expect(find.textContaining('已交给系统远程桌面客户端'), findsOneWidget);
  });
}

class _FakeRemoteSession implements RemoteSessionHandle {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  final List<String> sentLines = <String>[];

  @override
  bool running = true;

  void addOutput(String value) => _output.add(value);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  void sendLine(String line) => sentLines.add(line);

  @override
  Future<void> stop() async {
    if (!running) return;
    running = false;
    if (!_exit.isCompleted) _exit.complete(0);
    await _output.close();
  }
}

class _FakeInteractiveRemoteSession extends _FakeRemoteSession
    implements RemoteInteractiveSessionHandle {
  final List<String> sentData = <String>[];
  final List<(int, int)> sizes = <(int, int)>[];

  @override
  void send(String data) => sentData.add(data);

  @override
  void resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    sizes.add((columns, rows));
  }
}

class _FakeRemoteFileClient implements RemoteFileClient {
  bool closed = false;

  @override
  Future<String> absolute(String path) async => '/';

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async =>
      const <RemoteFileEntry>[];

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
  Future<void> close() async => closed = true;
}

class _FakePortForwardConnection implements PortForwardConnection {
  final Completer<void> _done = Completer<void>();
  final List<PortForwardSpec> specs = <PortForwardSpec>[];
  final List<_FakePortForwardHandle> handles = <_FakePortForwardHandle>[];
  int? failPort;

  @override
  bool connected = true;

  @override
  Future<void> get done => _done.future;

  @override
  Future<PortForwardHandle> start(PortForwardSpec spec) async {
    if (spec.listenPort == failPort) {
      throw StateError('本地端口 ${spec.listenPort} 已占用');
    }
    specs.add(spec);
    final _FakePortForwardHandle handle = _FakePortForwardHandle(spec);
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> close() async {
    if (!connected) return;
    connected = false;
    for (final _FakePortForwardHandle handle in handles) {
      await handle.stop();
    }
    if (!_done.isCompleted) _done.complete();
  }
}

class _FakePortForwardHandle implements PortForwardHandle {
  _FakePortForwardHandle(this.spec);

  @override
  final PortForwardSpec spec;

  @override
  bool running = true;

  @override
  Future<void> stop() async => running = false;
}
