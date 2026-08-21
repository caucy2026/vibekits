import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'windows_test_node_service.dart';

enum WindowsNodeHelperOperation { apply, rollback, syncDevices }

enum WindowsNodeHelperActionStatus {
  succeeded,
  skipped,
  failed,
  cancelled,
  requiresRestart,
}

class WindowsNodeHelperRequest {
  WindowsNodeHelperRequest({
    required this.protocolVersion,
    required this.operation,
    required this.planId,
    required this.planDigest,
    required this.inspectionDigest,
    required this.nonce,
    required this.issuedAt,
    required this.expiresAt,
    required List<String> actionIds,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) : actionIds = List<String>.unmodifiable(actionIds),
       parameters = Map<String, Object?>.unmodifiable(parameters) {
    // Construction validates the envelope relative to its issue time. The
    // launcher/replay guard validates it again against the actual current time.
    WindowsNodeHelperProtocol.validateRequest(this, now: issuedAt);
  }

  static const int currentProtocolVersion = 1;

  final int protocolVersion;
  final WindowsNodeHelperOperation operation;
  final String planId;
  final String planDigest;
  final String inspectionDigest;
  final String nonce;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final List<String> actionIds;
  final Map<String, Object?> parameters;

  factory WindowsNodeHelperRequest.fromPlan({
    required WindowsNodeChangePlan plan,
    required String nonce,
    required DateTime issuedAt,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) => WindowsNodeHelperRequest(
    protocolVersion: currentProtocolVersion,
    operation: WindowsNodeHelperOperation.apply,
    planId: plan.id,
    planDigest: plan.digest,
    inspectionDigest: plan.inspectionDigest,
    nonce: nonce,
    issuedAt: issuedAt,
    expiresAt: plan.expiresAt,
    actionIds: plan.actions
        .map((WindowsNodePlanAction item) => item.id)
        .toList(),
    parameters: parameters,
  );

  Map<String, Object?> payload() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'operation': operation.name,
    'planId': planId,
    'planDigest': planDigest,
    'inspectionDigest': inspectionDigest,
    'nonce': nonce,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'actionIds': actionIds,
    'parameters': parameters,
  };

  String get digest => WindowsNodeHelperProtocol.digest(payload());

  Map<String, Object?> toJson() => <String, Object?>{
    ...payload(),
    'requestDigest': digest,
  };
}

class WindowsNodeHelperActionReceipt {
  const WindowsNodeHelperActionReceipt({
    required this.actionId,
    required this.status,
    required this.beforeDigest,
    required this.afterDigest,
    required this.detail,
    required this.elapsedMilliseconds,
  });

  final String actionId;
  final WindowsNodeHelperActionStatus status;
  final String beforeDigest;
  final String afterDigest;
  final String detail;
  final int elapsedMilliseconds;

  factory WindowsNodeHelperActionReceipt.fromJson(Map<String, Object?> json) {
    final WindowsNodeHelperActionStatus? status = WindowsNodeHelperActionStatus
        .values
        .where(
          (WindowsNodeHelperActionStatus item) => item.name == json['status'],
        )
        .firstOrNull;
    if (status == null) throw const FormatException('helper 动作状态无效');
    return WindowsNodeHelperActionReceipt(
      actionId: '${json['actionId'] ?? ''}',
      status: status,
      beforeDigest: '${json['beforeDigest'] ?? ''}',
      afterDigest: '${json['afterDigest'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      elapsedMilliseconds: int.tryParse('${json['elapsedMilliseconds']}') ?? -1,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'status': status.name,
    'beforeDigest': beforeDigest,
    'afterDigest': afterDigest,
    'detail': detail,
    'elapsedMilliseconds': elapsedMilliseconds,
  };
}

class WindowsNodeHelperReceipt {
  const WindowsNodeHelperReceipt({
    required this.protocolVersion,
    required this.requestDigest,
    required this.nonce,
    required this.receiptId,
    required this.completedAt,
    required this.actions,
  });

  final int protocolVersion;
  final String requestDigest;
  final String nonce;
  final String receiptId;
  final DateTime completedAt;
  final List<WindowsNodeHelperActionReceipt> actions;

  factory WindowsNodeHelperReceipt.fromJson(Map<String, Object?> json) {
    final Object? rawActions = json['actions'];
    if (rawActions is! List) throw const FormatException('helper 回执缺少动作结果');
    return WindowsNodeHelperReceipt(
      protocolVersion: int.tryParse('${json['protocolVersion']}') ?? 0,
      requestDigest: '${json['requestDigest'] ?? ''}',
      nonce: '${json['nonce'] ?? ''}',
      receiptId: '${json['receiptId'] ?? ''}',
      completedAt:
          DateTime.tryParse('${json['completedAt'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      actions: List<WindowsNodeHelperActionReceipt>.unmodifiable(
        rawActions.map((Object? item) {
          if (item is! Map) throw const FormatException('helper 动作回执格式无效');
          return WindowsNodeHelperActionReceipt.fromJson(
            item.map(
              (dynamic key, dynamic value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          );
        }),
      ),
    );
  }
}

abstract final class WindowsNodeHelperProtocol {
  static const Set<String> allowedActionIds = <String>{
    'windows.openssh.install_or_repair',
    'windows.sshd.configure',
    'windows.sshd.start_and_enable',
    'windows.network.mark_private',
    'windows.firewall.apply_lan_rule',
    'windows.local_user.create_standard',
    'windows.local_user.set_authorized_keys',
    'windows.acl.apply_test_root',
    'windows.runtime.install_powershell',
    'windows.power.disable_ac_sleep',
    'windows.rollback.restore',
    'windows.devices.sync_authorized_keys',
  };

  static const Set<String> forbiddenParameterNames = <String>{
    'command',
    'cmd',
    'script',
    'shell',
    'executable',
    'arguments',
    'powershell',
  };

  static void validateRequest(
    WindowsNodeHelperRequest request, {
    DateTime? now,
  }) {
    if (request.protocolVersion !=
        WindowsNodeHelperRequest.currentProtocolVersion) {
      throw const FormatException('helper 协议版本不受支持');
    }
    if (!_token(request.planId) || !_token(request.nonce, minimum: 16)) {
      throw const FormatException('plan ID 或 nonce 无效');
    }
    if (!_sha256(request.planDigest) || !_sha256(request.inspectionDigest)) {
      throw const FormatException('计划或体检摘要无效');
    }
    final DateTime current = now ?? DateTime.now();
    if (!request.expiresAt.isAfter(current) ||
        request.expiresAt.difference(request.issuedAt) >
            const Duration(minutes: 15) ||
        request.issuedAt.isAfter(current.add(const Duration(minutes: 1)))) {
      throw const FormatException('helper 请求已过期或时效范围无效');
    }
    if (request.actionIds.isEmpty ||
        request.actionIds.toSet().length != request.actionIds.length) {
      throw const FormatException('helper 动作不能为空或重复');
    }
    if (request.actionIds.any((String id) => !allowedActionIds.contains(id))) {
      throw const FormatException('helper 请求包含未知 action ID');
    }
    _rejectShellLikeValues(request.parameters);
  }

  static void validateReceipt(
    WindowsNodeHelperRequest request,
    WindowsNodeHelperReceipt receipt,
  ) {
    if (receipt.protocolVersion != request.protocolVersion ||
        receipt.requestDigest != request.digest ||
        receipt.nonce != request.nonce ||
        !_token(receipt.receiptId)) {
      throw const FormatException('helper 回执与请求不匹配');
    }
    final List<String> ids = receipt.actions
        .map((WindowsNodeHelperActionReceipt item) => item.actionId)
        .toList(growable: false);
    if (ids.length != ids.toSet().length ||
        ids.any((String id) => !request.actionIds.contains(id))) {
      throw const FormatException('helper 回执包含重复或越权动作');
    }
    for (final WindowsNodeHelperActionReceipt action in receipt.actions) {
      if (!_sha256(action.beforeDigest) ||
          !_sha256(action.afterDigest) ||
          action.elapsedMilliseconds < 0) {
        throw const FormatException('helper 动作回执证据无效');
      }
    }
  }

  static String digest(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final List<String> keys = value.keys.map((Object? key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList(growable: false);
    return value;
  }

  static void _rejectShellLikeValues(Object? value, [String key = '']) {
    if (forbiddenParameterNames.contains(key.toLowerCase())) {
      throw const FormatException('helper 参数禁止携带命令、脚本或可执行文本');
    }
    if (value is Map) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        _rejectShellLikeValues(entry.value, '${entry.key}');
      }
    } else if (value is List) {
      for (final Object? item in value) {
        _rejectShellLikeValues(item, key);
      }
    }
  }

  static bool _token(String value, {int minimum = 8}) =>
      RegExp('^[A-Za-z0-9_-]{$minimum,128}\$').hasMatch(value);
  static bool _sha256(String value) =>
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
}

class WindowsNodeHelperReplayGuard {
  final Set<String> _consumedNonces = <String>{};

  void accept(WindowsNodeHelperRequest request, {DateTime? now}) {
    WindowsNodeHelperProtocol.validateRequest(request, now: now);
    if (!_consumedNonces.add(request.nonce)) {
      throw const FormatException('helper nonce 已使用，拒绝重放');
    }
  }
}
