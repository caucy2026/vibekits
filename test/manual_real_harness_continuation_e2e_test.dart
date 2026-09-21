import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/platform_storage_layout.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_agent_preferences.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_coordinator.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_summarizer.dart';
import 'package:vibekits/features/dev_tools/domain/harness_continuation_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_official_remote_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lifecycle = MethodChannel('vibekits/process_lifecycle');
  final enabled = Platform.environment['VIBEKITS_REAL_CONTINUATION_E2E'] == '1';

  setUpAll(() async {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycle, (call) async => true);
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycle, null);
  });

  test(
    'real official Harness summarizes and creates a linked empty session',
    () async {
      final workspacePath =
          Platform.environment['VIBEKITS_CONTINUATION_WORKSPACE'] ??
          '/Volumes/ORICO/harness';
      final port = await DeepSeekHarnessService.findFreeLoopbackPort();
      final handle = await DeepSeekHarnessService.startWebAgent(
        HarnessWebRequest(
          workspace: workspacePath,
          apiKey: '',
          port: port,
          permissionMode: HarnessAgentPermissionMode.assisted,
          approveTool: (_) async => false,
        ),
      );
      addTearDown(() async {
        await handle.stop();
      });
      final authenticatedUrl = await _announcedUrl(handle);
      await _ready(authenticatedUrl.replace(query: null));
      final adapter = HarnessOfficialRemoteAdapter(authenticatedUrl);
      addTearDown(adapter.close);
      final workspaces = await _workspaceSnapshot(adapter);
      final workspace = workspaces.firstWhere(
        (row) =>
            row['sessionIds'] is List && (row['sessionIds'] as List).isNotEmpty,
      );
      final workspaceId = workspace['workspaceId'] as String;
      final sourceSessionId = (workspace['sessionIds'] as List).last as String;
      final history = await adapter.request(<String, dynamic>{
        'type': 'client-request',
        'rpcId': 'continuation-source',
        'method': 'session.history',
        'payload': <String, Object?>{'sessionId': sourceSessionId, 'cursor': 0},
      });
      final value = ((history['result'] as Map)['value'] as Map);
      final header = value['header'] as Map?;
      final sourceTitle = '${header?['title'] ?? '真实验收会话'}';
      final stages = <String>[];
      final store = HarnessContinuationStore(
        home: Directory(
          '${PlatformStorageLayout.current().harnessHomeDirectory}'
          '${Platform.pathSeparator}continuations',
        ),
      );
      final coordinator = HarnessContinuationCoordinator(
        adapter: adapter,
        store: store,
        timeout: const Duration(minutes: 3),
        summarizer: HarnessContinuationSummarizer(
          adapter: adapter,
          timeout: const Duration(minutes: 3),
        ).summarize,
      );
      final record = await coordinator.create(
        workspace: workspaceId,
        workspaceId: workspaceId,
        sourceSessionId: sourceSessionId,
        sourceTitle: sourceTitle,
        onProgress: stages.add,
      );
      expect(record.summary, isNotEmpty);
      final sourceRecords = value['records'] as List;
      final hasSourceMessages = sourceRecords.any((raw) {
        if (raw is! Map) return false;
        final event = raw['event'] is Map ? raw['event'] as Map : raw;
        return const {
          'user/message',
          'assistant/message',
        }.contains(event['type']);
      });
      if (hasSourceMessages) {
        expect(record.summary, isNot(contains('来源会话暂无可提取的对话正文')));
      }
      expect(record.continuationSessionId, isNot(sourceSessionId));
      expect(
        HarnessContinuationCoordinator.requiredSections.every(
          record.summary.contains,
        ),
        isTrue,
      );
      final childHistory = await adapter.request(<String, dynamic>{
        'type': 'client-request',
        'rpcId': 'continuation-child',
        'method': 'session.history',
        'payload': <String, Object?>{
          'sessionId': record.continuationSessionId,
          'cursor': 0,
        },
      });
      final childValue = ((childHistory['result'] as Map)['value'] as Map);
      final childRecords = childValue['records'] as List;
      expect(
        childRecords.where((record) {
          if (record is! Map) return false;
          final event = record['event'] is Map ? record['event'] : record;
          if (event is! Map) return false;
          return const {
            'user/message',
            'assistant/message',
          }.contains(event['type']);
        }),
        isEmpty,
      );
      final persisted = await store.sourceFor(
        workspaceId,
        record.continuationSessionId,
      );
      expect(persisted, isNotNull);
      expect(persisted!.sourceSessionId, sourceSessionId);
      expect(persisted.continuationSessionId, record.continuationSessionId);
      expect(persisted.summary, record.summary);
      // ignore: avoid_print
      print(
        'HARNESS_CONTINUATION_E2E_OK source=$sourceSessionId '
        'child=${record.continuationSessionId} stages=${stages.join(' > ')}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_CONTINUATION_E2E=1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<Uri> _announcedUrl(HarnessSessionHandle handle) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final url = handle.url;
    if ((url.queryParameters['token'] ?? '').isNotEmpty) return url;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Harness authenticated URL was not announced');
}

Future<List<Map<String, dynamic>>> _workspaceSnapshot(
  HarnessOfficialRemoteAdapter adapter,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      return await adapter.workspaceSnapshot();
    } on Object catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw TimeoutException('Workspace snapshot unavailable: $lastError');
}

Future<void> _ready(Uri endpoint) async {
  final client = HttpClient();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(endpoint);
        request.followRedirects = false;
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode >= 200 && response.statusCode < 500) return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw TimeoutException('Harness web did not become ready');
  } finally {
    client.close(force: true);
  }
}
