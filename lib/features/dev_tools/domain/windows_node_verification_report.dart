enum NodeVerificationStatus { passed, failed, cancelled }

class NodeVerificationCheck {
  const NodeVerificationCheck({
    required this.id,
    required this.passed,
    required this.elapsedMilliseconds,
    required this.detail,
    required this.evidenceRefs,
  });

  final String id;
  final bool passed;
  final int elapsedMilliseconds;
  final String detail;
  final List<String> evidenceRefs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'passed': passed,
    'elapsedMilliseconds': elapsedMilliseconds,
    'detail': detail,
    'evidenceRefs': evidenceRefs,
  };
}

class NodeVerificationReport {
  NodeVerificationReport({
    required this.id,
    required this.sourceDeviceId,
    required this.sourceDeviceLabel,
    required this.sourcePlatform,
    required this.targetHost,
    required this.hostKeyFingerprint,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    required List<NodeVerificationCheck> checks,
  }) : checks = List<NodeVerificationCheck>.unmodifiable(checks) {
    validate();
  }

  static const Set<String> requiredCheckIds = <String>{
    'host_key_pinned',
    'public_key_login',
    'pwsh_no_profile',
    'work_directory',
    'temp_directory',
    'sftp_upload_sha256',
    'sftp_download_sha256',
    'sftp_cancel_no_residue',
    'network_drop_retry',
    'firewall_scope',
    'reconnect_same_host_key',
  };

  final String id;
  final String sourceDeviceId;
  final String sourceDeviceLabel;
  final String sourcePlatform;
  final String targetHost;
  final String hostKeyFingerprint;
  final DateTime startedAt;
  final DateTime completedAt;
  final NodeVerificationStatus status;
  final List<NodeVerificationCheck> checks;

  void validate() {
    if (sourceDeviceId.trim().isEmpty || sourceDeviceLabel.trim().isEmpty) {
      throw const FormatException('验证报告缺少来源设备身份');
    }
    final String platform = sourcePlatform.trim().toLowerCase();
    if (platform != 'macos' && platform != 'windows' && platform != 'linux') {
      throw const FormatException('验证来源平台无效');
    }
    final String host = targetHost.trim().toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1') {
      throw const FormatException('跨设备验收不能使用本机 localhost');
    }
    if (!hostKeyFingerprint.startsWith('SHA256:')) {
      throw const FormatException('验证报告必须固定 SHA-256 host key');
    }
    if (completedAt.isBefore(startedAt)) throw const FormatException('验证耗时无效');
    final Set<String> ids = checks
        .map((NodeVerificationCheck item) => item.id)
        .toSet();
    if (ids.length != checks.length || !ids.containsAll(requiredCheckIds)) {
      throw const FormatException('验证报告缺少必需检查或包含重复检查');
    }
    for (final NodeVerificationCheck check in checks) {
      if (check.elapsedMilliseconds < 0 || check.detail.length > 500) {
        throw const FormatException('验证检查耗时或摘要无效');
      }
      for (final String evidence in check.evidenceRefs) {
        final String lower = evidence.toLowerCase();
        if (evidence.length > 500 ||
            lower.contains('password=') ||
            lower.contains('private key') ||
            lower.contains('begin openssh')) {
          throw const FormatException('证据引用包含秘密或正文');
        }
      }
    }
    if (status == NodeVerificationStatus.passed &&
        checks.any((NodeVerificationCheck item) => !item.passed)) {
      throw const FormatException('存在失败检查时不能标记整体通过');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'reportId': id,
    'sourceDeviceId': sourceDeviceId,
    'sourceDeviceLabel': sourceDeviceLabel,
    'sourcePlatform': sourcePlatform,
    'targetHost': targetHost,
    'hostKeyFingerprint': hostKeyFingerprint,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'elapsedMilliseconds': completedAt.difference(startedAt).inMilliseconds,
    'status': status.name,
    'checks': checks
        .map((NodeVerificationCheck item) => item.toJson())
        .toList(),
  };
}

class WorkflowArtifact {
  const WorkflowArtifact({
    required this.type,
    required this.createdAt,
    required this.summary,
    required this.payload,
    required this.nextSteps,
  });

  final String type;
  final DateTime createdAt;
  final String summary;
  final Map<String, Object?> payload;
  final List<String> nextSteps;

  factory WorkflowArtifact.fromNodeVerification(
    NodeVerificationReport report,
  ) => WorkflowArtifact(
    type: 'windows_node_verification',
    createdAt: report.completedAt,
    summary:
        '${report.sourceDeviceLabel} → ${report.targetHost}：${report.status.name}',
    payload: report.toJson(),
    nextSteps: report.status == NodeVerificationStatus.passed
        ? const <String>['登记最近连接时间', '保留脱敏证据', '可继续单设备撤销验收']
        : const <String>['保持密码认证门禁', '修复失败检查', '从同一来源设备重新验证'],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'summary': summary,
    'payload': payload,
    'nextSteps': nextSteps.take(3).toList(growable: false),
  };
}
