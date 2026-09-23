import 'dart:io';

import 'harness_official_remote_adapter.dart';

class HarnessContinuationSource {
  const HarnessContinuationSource({
    required this.workspaceId,
    required this.sessionId,
    required this.title,
  });

  final String workspaceId;
  final String sessionId;
  final String title;
}

/// Resolves the selected official Harness row without relying on private DOM
/// attributes. Some DSH builds expose only a title in the session tree.
class HarnessContinuationSourceResolver {
  HarnessContinuationSourceResolver(this.adapter);

  final HarnessRemoteApiAdapter adapter;

  Future<HarnessContinuationSource> resolve({
    String requestedSessionId = '',
    String requestedTitle = '',
  }) => _resolve(
    requestedSessionId: requestedSessionId,
    requestedTitle: requestedTitle,
  ).timeout(const Duration(seconds: 15));

  Future<HarnessContinuationSource> _resolve({
    required String requestedSessionId,
    required String requestedTitle,
  }) async {
    final workspaces = await adapter.workspaceSnapshot();
    final requestedId = requestedSessionId.trim();
    final title = _normaliseTitle(requestedTitle);
    final candidates = <(String, String)>[];
    for (final workspace in workspaces) {
      final workspaceId = workspace['workspaceId']?.toString().trim() ?? '';
      final sessionIds = workspace['sessionIds'];
      if (workspaceId.isEmpty || sessionIds is! List) continue;
      for (final rawId in sessionIds) {
        final sessionId = rawId.toString().trim();
        if (sessionId.isEmpty) continue;
        if (requestedId == sessionId) {
          return HarnessContinuationSource(
            workspaceId: workspaceId,
            sessionId: sessionId,
            title: title.isEmpty ? '未命名会话' : title,
          );
        }
        candidates.add((workspaceId, sessionId));
      }
    }
    if (title.isEmpty) throw const FormatException('无法识别当前 Harness 会话');
    final resolved = await Future.wait(
      candidates.reversed.where((_) => requestedId.isEmpty).map((
        candidate,
      ) async {
        try {
          final response = await adapter.request(<String, dynamic>{
            'type': 'client-request',
            'rpcId': 'resolve-${candidate.$2}',
            'method': 'session.history',
            'payload': <String, Object?>{
              'sessionId': candidate.$2,
              'cursor': 0,
            },
          }, timeout: const Duration(seconds: 5));
          final result = response['result'];
          final value = result is Map ? result['value'] : null;
          final projections = value is Map ? value['projections'] : null;
          final projectionValues = projections is Map
              ? projections['values']
              : null;
          final candidateTitle = projectionValues is Map
              ? _normaliseTitle(projectionValues['title']?.toString() ?? '')
              : '';
          return candidateTitle == title
              ? HarnessContinuationSource(
                  workspaceId: candidate.$1,
                  sessionId: candidate.$2,
                  title: candidateTitle,
                )
              : null;
        } on Object {
          return null;
        }
      }),
    );
    final matches = resolved.whereType<HarnessContinuationSource>().toList();
    if (matches.length > 1) {
      throw FormatException('存在多个同名会话，请先为目标会话设置唯一名称：$title');
    }
    if (matches.length == 1) return matches.single;
    // Official DSH can show ungrouped sessions in the sidebar without adding
    // their IDs to a workspace's sessionIds. Its session/list still exposes
    // the persisted ID, title and cwd. Match cwd to an existing workspace
    // path exactly so a title-only action never derives from another project.
    final response = await adapter.request(<String, dynamic>{
      'type': 'client-request',
      'rpcId': 'resolve-ungrouped',
      'method': 'session.list',
      'payload': const <String, Object?>{},
    }, timeout: const Duration(seconds: 5));
    final result = response['result'];
    final value = result is Map ? result['value'] : null;
    final items = value is Map ? value['items'] : null;
    final ungrouped = <HarnessContinuationSource>[];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['sessionId']?.toString().trim() ?? '';
        final projections = item['projections'];
        final values = projections is Map ? projections['values'] : null;
        final itemTitle = values is Map
            ? _normaliseTitle(values['title']?.toString() ?? '')
            : '';
        if (id.isEmpty ||
            (requestedId.isNotEmpty ? id != requestedId : itemTitle != title)) {
          continue;
        }
        final sourcePath = item['cwd']?.toString().trim() ?? '';
        final cwd = _normalisePath(sourcePath);
        final owners = workspaces.where(
          (workspace) =>
              cwd.isNotEmpty &&
              _normalisePath(workspace['path']?.toString() ?? '') == cwd,
        );
        String workspaceId;
        if (owners.isEmpty &&
            requestedId == id &&
            Directory(sourcePath).isAbsolute &&
            adapter is HarnessRemoteWorkspaceProvisioner) {
          // A fresh official catalog may contain only ungrouped sessions.
          // Provision only the explicitly clicked session's persisted cwd;
          // never infer a new workspace from a title or the current selection.
          workspaceId = await (adapter as HarnessRemoteWorkspaceProvisioner)
              .ensureWorkspacePath(sourcePath);
        } else if (owners.length == 1) {
          workspaceId = owners.single['workspaceId']?.toString().trim() ?? '';
        } else {
          continue;
        }
        if (workspaceId.isEmpty) continue;
        ungrouped.add(
          HarnessContinuationSource(
            workspaceId: workspaceId,
            sessionId: id,
            title: itemTitle.isEmpty ? title : itemTitle,
          ),
        );
      }
    }
    if (ungrouped.length > 1) {
      throw FormatException('存在多个同名会话，请先为目标会话设置唯一名称：$title');
    }
    if (ungrouped.length == 1) {
      final source = ungrouped.single;
      // Persist the source in the same official workspace as its child.
      // Otherwise returning to an ungrouped source loses workspace-scoped
      // relations and makes the blank child disappear from the sidebar.
      final attached = await adapter.request(<String, dynamic>{
        'type': 'client-request',
        'rpcId': 'attach-continuation-source',
        // session.create with an existing ID idempotently adopts it; the
        // workspace ordering API can only move already attached sessions.
        'method': 'session.create',
        'payload': <String, Object?>{
          'workspaceId': source.workspaceId,
          'sessionId': source.sessionId,
        },
      }, timeout: const Duration(seconds: 5));
      final result = attached['result'];
      final value = result is Map ? result['value'] : null;
      if (result is! Map ||
          result['ok'] != true ||
          value is! Map ||
          value['sessionId'] != source.sessionId) {
        throw const FormatException('无法保存来源会话的工作区归属');
      }
      return source;
    }
    throw FormatException('未找到会话：《$title》');
  }

  static String _normalisePath(String value) {
    final path = value
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'(?<=.)/+$'), '');
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  static String _normaliseTitle(String value) => value
      .replaceFirst(RegExp(r'\s*(刚刚|\d+\s*(秒|分钟|小时|天|周|个月|月|年)(前)?)$'), '')
      .trim();
}
